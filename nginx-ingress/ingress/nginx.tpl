user  nginx;
worker_processes  1;

error_log /dev/fd/2 warn;
pid /var/run/nginx.pid;

events {
    worker_connections  1024;
}

{% if proxy_mode == 'ssl-passthrough' -%}
stream {
    map $ssl_preread_server_name $name {
        {% for service in services -%}
        {% if service['https_config'] and proxy_mode == 'ssl-passthrough' -%}
        {{ service['virtual_host'] }}       backend-{{ service['service_name'] }};
        {% endif -%}
        {% endfor %}
    }
  
    {% for service in services -%}
    {% if service['https_config'] and proxy_mode == 'ssl-passthrough' -%}
    # {{ service['virtual_host'] }} - {{ service['service_id'] }} - HTTPS Passthrough
    upstream backend-{{ service['service_name'] }} {
        server {{ service['service_name'] }}:443;
    }
    {% endif -%}
    {% endfor %}
    proxy_protocol on;
  
    server {
        listen      443;
        proxy_pass  $name;
        ssl_preread on;
    }
}
{% endif %}

http {
    resolver 127.0.0.11 ipv6=off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format default '{{ log_pattern }}';
    access_log /dev/fd/1 default;

    sendfile on;
    keepalive_timeout 65;

    # If we receive X-Forwarded-Proto, pass it through; otherwise, pass along the
    # scheme used to connect to this server
    map $http_x_forwarded_proto $proxy_x_forwarded_proto {
        default $http_x_forwarded_proto;
        ''      $scheme;
    }
    # If we receive X-Forwarded-Port, pass it through; otherwise, pass along the
    # server port the client connected to
    map $http_x_forwarded_port $proxy_x_forwarded_port {
        default $http_x_forwarded_port;
        ''      $server_port;
    }
    # If we receive Upgrade, set Connection to "upgrade"; otherwise, delete any
    # Connection header that may have been passed to this server
    map $http_upgrade $proxy_connection {
        default upgrade;
        '' close;
    }
    # Apply fix for very long server names
    server_names_hash_bucket_size 128;

    # Set appropriate X-Forwarded-Ssl header based on $proxy_x_forwarded_proto
        map $proxy_x_forwarded_proto $proxy_x_forwarded_ssl {
        default off;
        https on;
    }

    gzip_types text/plain text/css application/javascript application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
        
    # HTTP 1.1 support
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_set_header Host $http_host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $proxy_connection;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $proxy_x_forwarded_proto;
    proxy_set_header X-Forwarded-Ssl $proxy_x_forwarded_ssl;
    proxy_set_header X-Forwarded-Port $proxy_x_forwarded_port;

    proxy_set_header Proxy "";

    {% if request_id -%}
    proxy_set_header Request-Id $request_id;
    add_header Request-Id $request_id;
    {% endif %}

    server {
        listen 80;
        server_name _;
        access_log off;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
    }
    
    {% if proxy_mode not in ['ssl-passthrough'] -%}
    server {
        server_name _;
        listen 443 ssl http2 ;
        
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        charset utf-8;

        # SSL Settings        
        ssl_certificate /etc/nginx/default.crt;
        ssl_certificate_key /etc/nginx/default.key;
       
        include /etc/nginx/options-ssl-nginx.conf;
        ssl_dhparam /etc/nginx/ssl-dhparams.pem;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
    }
    {% endif %}

    # Define upstreams for all service backends (HTTP and HTTPS)
    {% for up in upstreams -%}
    upstream {{ up.name }} {
        server {{ up.target }};
    }
    {% endfor %}

    # Per-host servers with multiple path locations
    {% for h in hosts -%}
    {% set alt = h.alt_host %}

    # HTTP server for {{ h.host }}
    {% if h.has_http or (h.redirect_locations | length > 0) -%}
    server {
        listen 80;
        server_name {{ h.host }}{% if alt %} {{ alt }}{% endif %};
        charset utf-8;

        # Redirect-only paths
        {% for r in h.redirect_locations -%}
        {% if r.path_prefix != '/' -%}
        location = {{ r.path_exact }} {
            return 301 https://$host{{ r.path_prefix }};
        }
        location ^~ {{ r.path_prefix }} {
            return 301 https://$host$request_uri;
        }
        {% else %}
        # root path redirect is full-site redirect
        location / {
            return 301 https://$host$request_uri;
        }
        {% endif -%}
        {% endfor %}

        # Proxied HTTP paths
        {% for e in h.http_locations -%}
        {% if e.path_prefix != '/' -%}
        # normalize no-trailing-slash to trailing-slash
        location = {{ e.path_exact }} {
            return 301 $scheme://$host{{ e.path_prefix }};
        }
        location ^~ {{ e.path_prefix }} {
            {% if e.virtual_proto == 'https' -%}
            proxy_pass https://{{ e.upstream }}/;
            {% else -%}
            proxy_pass http://{{ e.upstream }}/;
            {% endif -%}
        }
        {% else %}
        # root mapping for this host
        location / {
            {% if e.virtual_proto == 'https' -%}
            proxy_pass https://{{ e.upstream }};
            {% else -%}
            proxy_pass http://{{ e.upstream }};
            {% endif -%}
        }
        {% endif -%}
        {% endfor %}
     }
    {% endif -%}

    # HTTPS server for {{ h.host }} (termination/bridging)
    {% if h.has_https and proxy_mode not in ['ssl-passthrough'] -%}
     server {
        server_name {{ h.host }}{% if alt %} {{ alt }}{% endif %};
        listen 443 ssl http2 ;
        
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        charset utf-8;

        # SSL Settings
        {% if h.certificate_name -%}
        ssl_certificate /run/secrets/{{ h.certificate_name }}.crt;
        ssl_certificate_key /run/secrets/{{ h.certificate_name }}.key;
        {% else %}
        ssl_certificate /run/secrets/{{ h.host }}.crt;
        ssl_certificate_key /run/secrets/{{ h.host }}.key;
        {% endif %}
        include /etc/nginx/options-ssl-nginx.conf;
        ssl_dhparam /etc/nginx/ssl-dhparams.pem;

        {% for e in h.https_locations -%}
        {% if e.path_prefix != '/' -%}
        # normalize no-trailing-slash to trailing-slash
        location = {{ e.path_exact }} {
            return 301 $scheme://$host{{ e.path_prefix }};
        }
        location ^~ {{ e.path_prefix }} {
            {% if e.virtual_proto == 'https' -%}
            proxy_pass https://{{ e.upstream }}/;
            {% else -%}
            proxy_pass http://{{ e.upstream }}/;
            {% endif -%}
         }
        {% else %}
        # root mapping for this host
        location / {
            {% if e.virtual_proto == 'https' -%}
            proxy_pass https://{{ e.upstream }};
            {% else -%}
            proxy_pass http://{{ e.upstream }};
            {% endif -%}
        }
        {% endif -%}
        {% endfor %}
        }
    }
    {% endif -%}
    {% endfor %}
}
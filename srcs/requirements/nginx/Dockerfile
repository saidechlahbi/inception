FROM debian:bookworm

RUN apt-get update && apt-get install -y nginx openssl && \ 
    	apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl 


RUN openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt  -keyout /etc/nginx/ssl/inception.key -subj "/CN=sechlahb.42.fr"

COPY conf/nginx.conf /etc/nginx/conf.d/nginx.conf

EXPOSE 443

ENTRYPOINT [ "nginx" , "-g", "daemon off;" ]
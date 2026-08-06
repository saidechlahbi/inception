FROM  debian:bookworm

RUN apt-get update && \
	apt-get install -y mariadb-server && \
	rm -rf /var/lib/apt/lists/* && rm -rf /var/lib/mysql/*

COPY ./tools/entrypoint.sh /usr/local/bin/entrypoint.sh

#bind-address = 127.0.0.1 to 0.0.0.0
#sed — stream editor, reads a file line by line and applies a transformation.
#-i — "in-place": write changes directly back into the file, instead of printing the result
RUN sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf


RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

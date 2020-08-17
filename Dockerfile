FROM postgres:9.6

ENV PG_MAX_WAL_SENDERS 8
ENV PG_WAL_KEEP_SEGMENTS 8

RUN apt-get update  \ 
    && apt-get install iputils-ping dnsutils -y

RUN apt-get install apt-transport-https postgresql-9.6-repmgr -y 

RUN apt-get install net-tools -y

COPY users.sh /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY setup.sh /docker-setup.sh

RUN chmod +x /docker-entrypoint.sh
RUN chmod +x /docker-setup.sh

ENTRYPOINT [ "./docker-setup.sh" ]
FROM python:2-alpine
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git bash curl coreutils bc \
 && pip install jarn.mkrelease docutils \
 && pip install -I wheel==0.31.0 

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]

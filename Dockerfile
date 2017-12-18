FROM python:2-alpine
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git bash curl \
 && pip install jarn.mkrelease

COPY docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

FROM python:2-alpine
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git bash curl coreutils bc \
 && pip install --upgrade pip \
 && pip install jarn.mkrelease docutils setuptools

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]

FROM python:2-alpine
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git bash curl coreutils bc npm yarn jq \
 && pip install docutils twine rstcheck \
 && pip install -I wheel==0.31.0 \
 && npm install -g release-it 

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]

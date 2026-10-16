FROM headwindmdm/hmdm:0.1.9

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb \
    && apt-get install -y /tmp/cloudflared.deb \
    && rm -f /tmp/cloudflared.deb \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/headwind-ptero-defaults \
    && cp -a /usr/local/tomcat/webapps /opt/headwind-ptero-defaults/webapps \
    && rm -rf /usr/local/tomcat/work /usr/local/tomcat/webapps /usr/local/tomcat/conf/Catalina/localhost \
    && mkdir -p /home/container/headwind/work /home/container/headwind/webapps /home/container/headwind/config \
    && ln -s /home/container/headwind/work /usr/local/tomcat/work \
    && ln -s /home/container/headwind/webapps /usr/local/tomcat/webapps \
    && ln -s /home/container/headwind/config /usr/local/tomcat/conf/Catalina/localhost

COPY ptero-entrypoint.sh /ptero-entrypoint.sh
RUN chmod 0755 /ptero-entrypoint.sh

EXPOSE 8080 8443 31000
ENTRYPOINT ["/ptero-entrypoint.sh"]
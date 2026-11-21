FROM node:24-bookworm-slim
WORKDIR /qayd
COPY --chown=node:node app/ ./app/
COPY --chown=node:node shared/ ./shared/
RUN install -d -m 0700 -o node -g node /data
ENV QAYD_DB=/data/qayd-shared.sqlite QAYD_HOST=0.0.0.0 PORT=3100 TZ=Asia/Aden
USER node
EXPOSE 3100
CMD ["node", "shared/server.cjs", "serve"]

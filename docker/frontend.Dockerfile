# Dev image for i-dolly-frontend, used by the root docker-compose.yaml. Lives here rather than in
# the frontend submodule because the frontend itself deploys to Vercel and doesn't need Docker.
# The source is bind-mounted over /app at runtime, so this image only has to supply node_modules.
FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 8080

# --host makes Vite listen on 0.0.0.0 so the published port is reachable from the host.
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

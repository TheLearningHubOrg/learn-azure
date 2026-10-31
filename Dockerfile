# Production Dockerfile for the learn-azure Functions app
# Stage 1: compile TypeScript and prune dev dependencies
FROM node:22-alpine AS builder
WORKDIR /src
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json host.json ./
COPY src ./src
COPY tests ./tests
RUN npm run build && npm test && npm prune --omit=dev

# Stage 2: Azure Functions host image (runs on Container Apps or a Premium plan)
FROM mcr.microsoft.com/azure-functions/node:4-node22 AS runner
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true
WORKDIR /home/site/wwwroot
COPY --from=builder /src/package.json /src/host.json ./
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/dist ./dist
EXPOSE 80

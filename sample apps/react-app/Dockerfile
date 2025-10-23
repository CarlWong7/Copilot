# Multi-stage build: build with Node, serve with nginx
FROM node:18-alpine AS build
WORKDIR /app

# Install dependencies (use npm ci for reproducible installs)
COPY package.json package-lock.json* ./
RUN npm ci --silent

# Copy the rest and build
COPY . .
RUN npm run build

### Production image
FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html

# Use custom nginx config to support client-side routing (SPA fallback)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

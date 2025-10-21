FROM node:18-slim

# Create app directory
WORKDIR /usr/src/app

# Copy package.json (no dependencies but keeps pattern) and source
COPY package.json .
COPY index.js .
COPY public ./public

# Expose port
EXPOSE 3000

# Start the server
CMD ["node", "index.js"]

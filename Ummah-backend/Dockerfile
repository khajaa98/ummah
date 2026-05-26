# Base image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install OpenSSL (required for Prisma on Alpine)
RUN apk add --no-cache openssl

# Copy package files first to leverage Docker layer caching
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the backend source code
COPY . .

# Generate Prisma Client
RUN npx prisma generate

# Expose the API port
EXPOSE 3000

# Start the server using the flat server.js file
CMD ["node", "server.js"]

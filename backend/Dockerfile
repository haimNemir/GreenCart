# Here we are using a multi-stage build to ?????????

# In the first stage:
# We take a Node.js environment, install all the tools and dependencies we need 
# (including TypeScript, and mongodb server to communicate with the DB) in the image, 
# copy the source code in "/app/dist" , and compile it from TypeScript into JavaScript.

# In the second stage:
# We create a new image (the final image we use), and install only the production
# dependencies such as "Express" and "mongodb server" (without TypeScript and 
# other development tools) and after that we copy the compiled JavaScript file from
# the first image in "/app/dist" to the second image in derectory "./dist".
# Finally, we define the command to run when the container starts, which is -
# "node dist/index.js" to run the compiled JavaScript file with the Node.js engine.



# Here we using node alpine as a minimal image for our app, and naming it "builder".
FROM node:20-alpine AS builder 
# Set the a working directory inside the container as directory "/app". 
WORKDIR /app
# Copy the package*.json to the directory "/app" (root now is "/app").
COPY package*.json ./
# Install the dependencies defined in package.json including the TypeScript.
RUN npm install
# Copy the config file of TypeScript to root.
COPY tsconfig.json ./
# Copy the source code of our app to the directory "/app/src".
COPY src/ ./src/
# Here we compile the TypeScript to JavaScript,and the output will be 
# automatically put in /app/dist as index.js.
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
# Insta
RUN npm install --omit=dev
COPY --from=builder /app/dist ./dist
# Document that the app backend listens on port 3000.
EXPOSE 3000
# Define the command to run when the container starts, which is - "node dist/index.js".
CMD ["node", "dist/index.js"]

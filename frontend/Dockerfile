# Here we are using the nginx image, and copying file to the image we download.
# So we do not need to "build" the image because nginx is already built and
# knows how to serve the files.  

FROM nginx:1.26-alpine
# Nginx save the index and the other files in "/usr/share/nginx/" folder.
COPY index.html /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80

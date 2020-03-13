
Docker Image
============

To support the App47 WebUI testing container.

* Ubuntu 14
* Mongo 3.0.15
* Redis
* Android build tools for 29.0.1
* Java 8
* Imagmagick

Docker commands that are useful
===============================

1. `docker build .` to build the current version
2. `docker login --username=%USERNAME%` to log into docker hub
2. `docker images` to list the images, with the most recent being at the top.
3. `docker tag %IMAGE ID% app47/webui-bionic:latest` to tag the local image
4. `docker push app47/webui-bionic` to push to the hub, this tag can then be used in circle ci files or other places.
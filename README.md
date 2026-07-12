
<!--#echo json="package.json" key="name" underline="=" -->
docker-alpine-tor-skimask
=========================
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
Let your whale host the latest onion.
<!--/#echo -->



Setup
-----

* Install docker v28 or later.
* Clone this repo.
* Configure: Create an empty text file `cfg.@local.rc`.
  * If you use an upstream proxy, add a line<br>
    `export https_proxy='http://your-proxy.example.net:3128/'`
* Make sure the container name "skimask" is unused,
  because that's the hard-coded container name for this project.



Usage
-----

* Run `./dkstart.sh`
* The container will be started in the background,
  and log output (`docker logs …`) will be streamed to your terminal.
* The start script inside the container will check available TOR versions,
  and if TOR is not installed yet, it will install it.
  * If multiple TOR versions are available, it will fail with a complaint
    about the comma and space in the TOR version. (It doesn't currently
    understand that there can be multiple version available.)
    This usually happens when your installed TOR is outdated, because then
    the package manager finds the local version and the latest available
    version. In that case, just `docker rm` the container and try again.
* Once everything looks like it works, quit the log viewer with `Ctrl`+`c`.



Known issues
------------

* Needs more/better tests and docs.





<!--#toc stop="scan" -->

&nbsp;


License
-------
<!--#echo json="package.json" key="license" -->
ISC
<!--/#echo -->

# Configizer for balenaOS config.json updates

Safe way to modify the `config.json` on a balenaOS device remotely (e.g. connecting over the [CLI][cli] using `balena ssh`)

This tool supports the `config.json` options provided by the operating system, that is not yet supported by the [supervisor][supervisor].
Any entry that the supervisor learns to support will be removed from this tool, as that is the right place for modifying values.

See the full list of the supported entries in the [meta-balena README][meta-balena readme].

## Usage

* `config.sh` is the script that will be run on the device. In the headers of that file, there are a number of settings, modify any of them that you want to use, leave the rest as it is. Only those modifications will be run on the device that are the non-default values. Each entry has a help text to assist in filling it out
* create a file called `batch`, and add the UUIDs of the devices that you want to modify there, one by one
* ensure that you are logged in with the CLI (e.g. by checking `balena whoami`)
* to run the script on the given devices, start with `./run.sh` (Linux is supported at the moment, might need to make that file executable, or run it with `bash ./run.sh`)
* you will see the logs of the updates, and those are also saved into a logfile
* if the script is re-run, any device that is successfully done previously (according to the `config.log` file) will be skipped. Thus if you change the script, and need to rerun on devices you run on previously, remove the `config.log` file.
* note, that once the script starts to run on a device, even if it gets disconnected (and thus logs stop) the `config.json` update will proceed

[cli]: https://github.com/balena-io/balena-cli/ "balenaCLI"
[supervisor]: https://github.com/balena-io/balena-supervisor "balena supervisor repository"
[meta-balena readme]: https://github.com/balena-os/meta-balena#configjson "Supported config.json values in balenaOS"
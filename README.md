# koha-plugin

This project is my attempt at doing the boring stuff less often. I hope it's useful to you!

Disclaimer: this project was stuck in my head for over a year, but at the time of writing it's 2 days old.
It's not a full-featured solution yet and definetly contains bugs (some I am already aware of).


## Badges

[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)


## Installation

### Plugins within Koha

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library.
Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages.
A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

### This project

I wanted to try out new features here, so you'll need `perl ^5.038`. If you're using an earlier version, I'd recommend checking out [perlbrew](https://perlbrew.pl/). 

There are some options, depending on what you prefer:
- Via [GitHub (pders01/koha-plugin)](https://github.com/pders01/koha-plugin)
    - Use the template button and create a new repository from the template.
    - Use the GitHub CLI: `$ gh repo create -p pders01/koha-plugin`.
- Just via git
```console
$ git clone https://github.com/pders01/koha-plugin.git "koha-plugin-$NAME"
$ cd "koha-plugin-$NAME"
$ rm -rf .git
$ git init
$ git remote add origin https://$HOST/$USER/koha-plugin-$NAME.git
```

The next thing you'll need is [Carton](https://metacpan.org/pod/Carton). You can install it with `$ cpanm carton` for example.
Then install the dependencies within the project root with `$ carton install`.

The last thing you'll need (optional but recommended) is [just](https://just.systems/).
Then you can just run `$ just` for an overview of commands in the project root.

You can of course just run the scripts without just. Take a look at the `justfile`.

Before you start, you should copy the env file from templates/env to .env in the project root and customize it (I will soon patch `just init` to prompt for this).
```console
$ cp templates/env .env
```


## License

[GPL v3](https://github.com/pders01/koha-plugin?tab=GPL-3.0-1-ov-file#readme)


## Support

For support, ping me on [Koha's Mattermost](https://chat.koha-community.org) __@paulderscheid__.


## Acknowledgements

 - [dev-koha-plugin-kitchen-sink](https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink) by [byWater Solutions](https://bywatersolutions.com) and [friends](https://chat.koha-community.org)
 - [Koha Community](https://koha-community.org)


## Contributing

Contributions are welcome! Just PR but please use `perltidy` and `perlimports` with the shipped configuration files.


## Demo

For example projects, check out:
- [koha-plugin-pomodoro](https://github.com/pders01/koha-plugin-pomodoro)
- [koha-plugin-command-palette](https://github.com/pders01/koha-plugin-command-palette) (This one is an example for a plugin that migrated to pders01/koha-plugin)


## Authors

- [@pders01](https://www.github.com/pders01)


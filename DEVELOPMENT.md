# Termify Development

## Dependencies

1. Make sure you have `ops` installed, in one of the following ways:
 - as a gem via `gem install ops_team` or
 - as a tool via `brew tap nickthecook/crops && brew install ops`
2. If you not using macOS, or a Linux that uses `apt`, please [install Crystal](https://crystal-lang.org/install/)

## Getting started

|Command                        |Description                                                                       |
|-------------------------------|----------------------------------------------------------------------------------|
|`ops up`                       |Gets everything setup including `crystal` via `apt` or `brew` if applicable.      |
|`ops build-debug` or `ops bd`  |Make a debug build of `benchmark` sample, in `bin/debug` folder.                  |
|`ops build-release` or `ops br`|Make a release / production build of `benchmark` sample,  in `bin/release` folder.|
|`ops lint`                     |Run `ameba` on the source code                                                    |
|`ops clean`                    |Remove debug and release build files                                              |
|`ops wipe`                     |In addition to cleaning, remove all compiler caches                               |

### Build and run for development

Use `ops run samples/<SOURCEFILE>` to compile and run the specific source.

### Build to run later

Run `ops build-release` to make a release build in the `bin/release/` folder

Run `ops build-debug` to make a debug build in the `bin/debug/` folder

## Samples

### `sampes/md2term`

This is a simple test app that reads a given Markdown file and renders it using Termify.

```sh
crystal run samples/mdterm.cr -- YOURMARKDOWNFILE.md
```

### `sampes/etst01`

This is a test app that has a Markdown string that it renders. I've been tweaking the Markdown to test aspects of the rendering.

```sh
crystal run samples/test01.cr
```

###

## Contributions

See [README](./README.md)

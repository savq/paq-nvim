Visit the [releases page](https://github.com/savq/paq-nvim/releases) for more details.

# Deprecations

### v1.0.0.

- The `hook` option was removed (use `run` instead).
- `:PaqRunHooks` was replaced by `:PaqRunHook`
- `paq-nvim` module alias was removed. call `require 'paq'` instead.

See #87 for more details.

### v0.9.0.

- The `'paq-nvim'` module has been renamed to `'paq'`.

- The command definitions have been moved from `plugin` to the lua module,
  to avoid calling commands (like `:PaqClean`), without having listed
  packages. This is technically a breaking change, but since the alternative
  is rather destructive (removing all your packages), and it's really unlikely
  any user relies on the commands existing before having `require`d the module,
  this has been done in this release rather than waiting for v1.0.


### v0.8.0.

Calling the `paq` function per package is deprecated. Users should now pass a
list to the `'paq-nvim'` module instead. See the readme and documentation for
more details.


### v0.6.0.

The `hook` option is deprecated. Use `run` instead.


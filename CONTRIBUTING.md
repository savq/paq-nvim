# Contributing

Paq is small because my own needs as a Nvim user are pretty simple,
but that doesn't mean I'm against adding features. If you have suggestions,
write an issue! Try to be specific. When writing the titles, make the intent clear;
and for the body of the issue, the more detailed the description the better.


## Issues

For bugs, write the title as an statement:
`Paq isn't doing foo` or `Paq does bar instead of foo`.
In the body, be sure to include the steps necessary to reproduce the issue,
and a minimal working example.

For feature requests, write the title as an imperative:
`Do foo instead of bar` or `Add foo`.
This makes it easier to match them to their (possible) corresponding PR.
In the body, try to nail down the scope of the feature, what it should do
and what it shouldn't do. Also include if you're interested in adding the
feature yourself.

For questions, there are no restrictions. Ask away. Just write the title a
question: `Can Paq do foo?`


## Development

Once an issue has been discussed, a PR with the necessary changes can be opened.
Paq is developed in a separate branch. PRs should fork from, and merge to `dev`.

The PR should mention the related issue, and explain how the changes were made.
Each commit message should also describe the specifics of each change.

Other notes:

- Changes should only affect code related to the issue, avoid cosmetic changes.
- Use the [luacheck](https://github.com/mpeterv/luacheck) linter to avoid common Lua mistakes.
- Paq doesn't use a code formatter. _Monkey see, monkey do._
  - Use double quotes for strings that will be used in I/O, including:
    paths, command line arguments, patterns, etc.
  - Use single quotes for strings pretending to be symbols,
    like the output of `type` or for table indexes.


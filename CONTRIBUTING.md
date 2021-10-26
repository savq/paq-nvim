# Contributing

Paq is small because my own needs as a Nvim user are pretty simple.
Before asking for a feature request, consider if using another package manager
which implements that feature would be better for you.


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

- Changes should only affect code related to the issue, avoid cosmetic changes.
- Use [StyLua](https://github.com/JohnnyMorganz/StyLua) for code formatting.
- Use [luacheck](https://github.com/mpeterv/luacheck) for linting.

# Contributing

Paq is small because my own needs as a Nvim user are pretty simple.
Before asking for a feature request, consider if using another package manager
which implements that feature would be better for you.

## Ask questions

For questions, there are no restrictions. Ask away.
Open a bare issue and write the question in the title. e.g. `Can Paq do foo?`


## File Bugs

Paq has an issue template for [reporting bugs](https://github.com/savq/paq-nvim/issues/new/choose).
Follow the instructions in the template and
make sure to write the title as an statement:
`Paq isn't doing foo` or `Paq does bar instead of foo`.


## Develop features

Before sending a PR, open an bare issue to discuss the feature.
Write the issue title as an imperative: `Do foo instead of bar` or `Add foo`,
this makes it easier to match it to a (possible) corresponding PR.

In the body, try to nail down the scope of the feature, what it should do and what it shouldn't do.
Make sure the feature doesn't already exist or is explicitly declared as something out of scope in the documentation.

Once an issue has been discussed, a PR with the necessary changes can be opened.

- Use a [feature branch](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow)
  instead of the default/master branch.
- Follow general git etiquette. Write meaningful commit messages.
- Changes should only affect code related to the issue, avoid cosmetic changes.
- Use [StyLua](https://github.com/JohnnyMorganz/StyLua) for code formatting.
  This repository includes a [`stylua.toml`](./.stylua.toml) file.


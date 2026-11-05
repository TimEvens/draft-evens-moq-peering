# draft-evens-moq-peering

* [Editor's Copy](https://timevens.github.io/draft-evens-moq-peering/#go.draft-evens-moq-peering.html)

## Contributing
See the [guidelines for contributions](CONTRIBUTING.md).

Contributions can be made by creating pull requests.
The GitHub interface supports creating pull requests using the Edit (✏) button.

## Generate HTML

```sh
make html
```

This writes `draft-evens-moq-peering.html`. `make` also builds the text form.
Publishing that HTML to the `gh-pages` branch, which GitHub Pages serves as the Editor's Copy, is `make gh-pages`.
Pushes to `main` run the same build in GitHub Actions and update the page.

This requires that you have the necessary software installed.  See
[the instructions](https://github.com/martinthomson/i-d-template/blob/master/doc/SETUP.md).

Since -13, you will also need `aasvg` and `svgcheck`.  First, install `npm`, then:

```sh
npm install -g aasvg
pip3 install svgcheck
```

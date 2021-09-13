final html404 = '''
<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>404 | Page not found.</title>

  <style type="text/css">
    body {
      padding: 30px 20px;
      font-family: -apple-system, BlinkMacSystemFont,
        "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell",
        "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
      color: #727272;
      line-height: 1.6;
    }

    .container {
      max-width: 500px;
      margin: 0 auto;
    }

    h1 {
      margin: 0 0 40px;
      font-size: 60px;
      line-height: 1;
      color: #252427;
      font-weight: 700;
    }

    h2 {
      margin: 100px 0 0;
      font-size: 20px;
      font-weight: 600;
      letter-spacing: 0.1em;
      color: #A299AC;
      text-transform: uppercase;
    }

    p {
      font-size: 16px;
      margin: 1em 0;
    }

    .go-back a {
      display: inline-block;
      margin-top: 3em;
      padding: 10px;
      color: #1B1A1A;
      font-weight: 700;
      border: solid 2px #e7e7e7;
      text-decoration: none;
      font-size: 16px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }

    .go-back a:hover {
      border-color: #1B1A1A;
    }

    @media screen and (min-width: 768px) {
      body {
        padding: 50px;
      }
    }

    @media screen and (max-width: 480px) {
      h1 {
        font-size: 48px;
      }
    }
  </style>
</head>
<body>

<div class="container">
  <h2>404</h2>
  <h1>Page not found.</h1>

  <p>We\u2019re sorry but it appears that we can\u2019t find the page you were looking for. Usually this occurs because of a page that previously existed was removed or you\u2019ve mistyped the address.</p>

  <span class="go-back"><a href="{{index}}">Go to index</a></span>
</div>

</body>
</html>
''';

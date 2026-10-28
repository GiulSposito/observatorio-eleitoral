# web/vendor/ — bibliotecas servidas localmente (opcional)

Por padrão o site carrega DuckDB-Wasm e Plotly do jsDelivr, com versão fixa em `web/js/vendor.js`,
e só quando uma aba de detalhe ou um gráfico interativo é aberto. Para servir tudo do próprio site:

```bash
mkdir -p web/vendor/plotly web/vendor/duckdb
curl -L -o web/vendor/plotly/plotly.min.js \
  https://cdn.jsdelivr.net/npm/plotly.js-dist-min@2.35.2/plotly.min.js
base=https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/dist
for f in duckdb-browser.mjs duckdb-mvp.wasm duckdb-browser-mvp.worker.js duckdb-eh.wasm duckdb-browser-eh.worker.js; do
  curl -L -o "web/vendor/duckdb/$f" "$base/$f"
done
```

Depois, em `web/js/vendor.js`, aponte `DUCKDB_URL` para `./vendor/duckdb/duckdb-browser.mjs` e
`PLOTLY_URL` para `./vendor/plotly/plotly.min.js`; em `web/js/data.js`, troque
`getJsDelivrBundles()` por um mapa `{ mvp, eh }` com os arquivos de `./vendor/duckdb/`.
Espere cerca de 15 MB, quase todo nos dois `.wasm`.

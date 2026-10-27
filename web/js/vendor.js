// Versões fixas das bibliotecas de runtime, carregadas sob demanda (fora do orçamento do
// primeiro paint): DuckDB-Wasm por js/data.js nas abas de detalhe; Plotly por js/charts.js
// quando um gráfico interativo é aberto. URL completa em vez de import map: o Quarto injeta
// scripts de módulo antes do <head> incluído, e o navegador ignora import maps tardios.
// Para servir localmente, troque por caminhos em vendor/ (ver web/vendor/README.md).

export const DUCKDB_URL = "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/+esm";
export const PLOTLY_URL = "https://cdn.jsdelivr.net/npm/plotly.js-dist-min@2.35.2/plotly.min.js";

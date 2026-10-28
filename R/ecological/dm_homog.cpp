// Núcleo numérico do motor dm-homog (05 §5.2): log-posterior Dirichlet-multinomial com taxas homogêneas
// e cadeia de passeio aleatório (Metropolis). Compilado sob demanda por ec_dm_cpp() (R/ecological/dm_homog.R).
//
// Parametrização: P[r, ] = softmax nas células livres da linha r. `pos` (R x C) indica, por célula, o
// índice do parâmetro em theta (>= 0), a célula de referência da linha (-1, logito 0) ou um zero
// estrutural (-2). O último elemento de theta é log(phi).
#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

static void theta_to_P(const NumericVector& theta, const IntegerMatrix& pos, NumericMatrix& P) {
  const int R = pos.nrow(), C = pos.ncol();
  for (int r = 0; r < R; r++) {
    double mx = -INFINITY;
    for (int c = 0; c < C; c++) {
      const int k = pos(r, c);
      if (k == -2) continue;
      const double v = (k >= 0) ? theta[k] : 0.0;
      if (v > mx) mx = v;
    }
    double s = 0.0;
    for (int c = 0; c < C; c++) {
      const int k = pos(r, c);
      const double e = (k == -2) ? 0.0 : std::exp(((k >= 0) ? theta[k] : 0.0) - mx);
      P(r, c) = e;
      s += e;
    }
    for (int c = 0; c < C; c++) P(r, c) /= s;
  }
}

static double logpost(const NumericVector& theta, const NumericMatrix& Xp, const NumericMatrix& Dm,
                      const NumericVector& N, const IntegerMatrix& pos, const double alpha,
                      const double lphi_lo, const double lphi_hi, const double mu, const double sd,
                      NumericMatrix& P) {
  const int R = pos.nrow(), C = pos.ncol(), n = Xp.nrow();
  const double lphi = theta[theta.size() - 1];
  if (!(lphi >= lphi_lo && lphi <= lphi_hi)) return R_NegInf;
  theta_to_P(theta, pos, P);
  const double phi = std::exp(lphi);
  const double lgphi = std::lgamma(phi);
  double ll = 0.0;
  for (int i = 0; i < n; i++) {
    ll += lgphi - std::lgamma(N[i] + phi);
    for (int c = 0; c < C; c++) {
      double q = 0.0;
      for (int r = 0; r < R; r++) q += Xp(i, r) * P(r, c);
      if (q < 1e-12) q = 1e-12;
      const double a = phi * q;
      ll += std::lgamma(Dm(i, c) + a) - std::lgamma(a);
    }
  }
  double lp = 0.0;
  for (int r = 0; r < R; r++)
    for (int c = 0; c < C; c++)
      if (pos(r, c) != -2) lp += alpha * std::log(std::max(P(r, c), 1e-300));
  lp += R::dnorm(lphi, mu, sd, true);
  return ll + lp;
}

// [[Rcpp::export]]
double dm_logpost_cpp(NumericVector theta, NumericMatrix Xp, NumericMatrix Dm, NumericVector N, IntegerMatrix pos,
                      double alpha, double lphi_lo, double lphi_hi, double mu, double sd) {
  NumericMatrix P(pos.nrow(), pos.ncol());
  return logpost(theta, Xp, Dm, N, pos, alpha, lphi_lo, lphi_hi, mu, sd, P);
}

// Avança uma cadeia de passeio aleatório: proposta theta + sc * L %*% z. Usa o RNG do R (set.seed).
// [[Rcpp::export]]
List dm_rw_chain_cpp(NumericVector theta0, NumericMatrix L, double sc, int iters, int thin,
                     NumericMatrix Xp, NumericMatrix Dm, NumericVector N, IntegerMatrix pos,
                     double alpha, double lphi_lo, double lphi_hi, double mu, double sd) {
  RNGScope scope;
  const int d = theta0.size();
  NumericMatrix P(pos.nrow(), pos.ncol());
  NumericVector th = clone(theta0), prop(d), z(d);
  double lp = logpost(th, Xp, Dm, N, pos, alpha, lphi_lo, lphi_hi, mu, sd, P);
  const int n_keep = iters / thin;
  NumericMatrix kept(n_keep, d);
  int acc = 0, k = 0;
  for (int it = 1; it <= iters; it++) {
    for (int j = 0; j < d; j++) z[j] = R::norm_rand();
    for (int a = 0; a < d; a++) {
      double s = 0.0;
      for (int b = 0; b < d; b++) s += L(a, b) * z[b];
      prop[a] = th[a] + sc * s;
    }
    const double lpp = logpost(prop, Xp, Dm, N, pos, alpha, lphi_lo, lphi_hi, mu, sd, P);
    if (R_FINITE(lpp) && std::log(R::unif_rand()) < lpp - lp) {
      for (int j = 0; j < d; j++) th[j] = prop[j];
      lp = lpp;
      acc++;
    }
    if (it % thin == 0 && k < n_keep) {
      for (int j = 0; j < d; j++) kept(k, j) = th[j];
      k++;
    }
  }
  return List::create(Named("kept") = kept, Named("theta") = th, Named("lp") = lp, Named("acc") = acc);
}

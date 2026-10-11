/**
 * Ylapalkin valikko.
 *
 * Linkit ovat samat ja samassa jarjestyksessa joka sivulla, ja tama
 * merkitsee niista sen jolla ollaan. Ilman merkintaa valikko nayttaa
 * samalta riippumatta siita missa ollaan, ja oikean napin etsiminen
 * aloitetaan alusta joka kerta.
 */
(function () {
  // Juuri ohjaa profiiliin, joten se merkitaan samaksi sivuksi.
  const polku = location.pathname.replace(/\/+$/, "") || "/profiili";

  for (const linkki of document.querySelectorAll(".valikko a[href]")) {
    if (linkki.getAttribute("href") === polku) {
      linkki.classList.add("nyt");
      linkki.setAttribute("aria-current", "page");
    }
  }
})();

/**
 * Nayttaa officerin linkit.
 *
 * Profiilisivu on ainoa jolle myos raider paasee, eika han saa nahda
 * linkkeja sivuille joilta hanet kaannytetaan. Sivu kutsuu tata kun se on
 * saanut tietaa roolin.
 */
window.naytaOfficerValikko = function () {
  for (const el of document.querySelectorAll(".valikko [data-officer]")) {
    el.hidden = false;
  }
};

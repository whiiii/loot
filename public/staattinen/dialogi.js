/**
 * Vahvistusikkuna selaimen confirmin tilalle.
 *
 * window.vahvista({ otsikko, teksti, vahvista, peruuta, varoitus })
 *   -> Promise<boolean>
 *
 * Palauttaa lupauksen, jotta kutsupaikka nayttaa samalta kuin aiemmin:
 *   if (!(await vahvista({...}))) return;
 */
(function () {
  function luoPeite() {
    const peite = document.createElement("div");
    peite.className = "dlg-peite";
    peite.hidden = true;

    peite.innerHTML = `
      <div class="dlg" role="dialog" aria-modal="true">
        <h3></h3>
        <p></p>
        <input type="text" class="dlg-syote" hidden>
        <div class="dlg-virhe" hidden></div>
        <div class="dlg-napit">
          <button type="button" class="dlg-peruuta"></button>
          <button type="button" class="dlg-vahvista"></button>
        </div>
      </div>`;

    document.body.appendChild(peite);
    return peite;
  }

  let peite = null;

  /**
   * Nayttaa ikkunan.
   *
   * Ilman syote-asetusta palauttaa true/false. Syotteen kanssa palauttaa
   * annetun tekstin tai null jos peruutettiin - tyhjaa arvoa ei hyvaksyta,
   * jottei kutsupaikan tarvitse erotella "peruutettiin" ja "jatettiin tyhjaksi".
   */
  window.vahvista = function (asetukset) {
    if (!peite) peite = luoPeite();

    const o = asetukset || {};
    const laatikko = peite.querySelector(".dlg");
    const nappiOk = peite.querySelector(".dlg-vahvista");
    const nappiEi = peite.querySelector(".dlg-peruuta");
    const syote = peite.querySelector(".dlg-syote");
    const virhe = peite.querySelector(".dlg-virhe");

    laatikko.classList.toggle("varoitus", !!o.varoitus);
    peite.querySelector("h3").textContent = o.otsikko || "Vahvista";
    peite.querySelector("p").textContent = o.teksti || "";
    nappiOk.textContent = o.vahvista || "Jatka";
    nappiEi.textContent = o.peruuta || "Peruuta";

    const kysyySyotetta = !!o.syote;
    syote.hidden = !kysyySyotetta;
    virhe.hidden = true;
    virhe.textContent = "";

    if (kysyySyotetta) {
      syote.type = o.syote.tyyppi || "text";
      syote.value = "";
      syote.placeholder = o.syote.vihje || "";
    }

    peite.hidden = false;
    (kysyySyotetta ? syote : nappiOk).focus();

    return new Promise((resolve) => {
      function sulje(tulos) {
        peite.hidden = true;
        nappiOk.removeEventListener("click", ok);
        nappiEi.removeEventListener("click", ei);
        peite.removeEventListener("click", ulkopuolelta);
        document.removeEventListener("keydown", nappain);
        resolve(tulos);
      }

      function ok() {
        if (!kysyySyotetta) { sulje(true); return; }

        const arvo = syote.value;
        const minimi = o.syote.minimi || 0;

        if (arvo.length < minimi) {
          virhe.textContent = o.syote.virhe || `Vähintään ${minimi} merkkiä.`;
          virhe.hidden = false;
          syote.focus();
          return;
        }
        sulje(arvo);
      }

      function ei() { sulje(kysyySyotetta ? null : false); }
      function ulkopuolelta(e) { if (e.target === peite) ei(); }
      function nappain(e) {
        if (e.key === "Escape") ei();
        if (e.key === "Enter") ok();
      }

      nappiOk.addEventListener("click", ok);
      nappiEi.addEventListener("click", ei);
      peite.addEventListener("click", ulkopuolelta);
      document.addEventListener("keydown", nappain);
    });
  };
})();

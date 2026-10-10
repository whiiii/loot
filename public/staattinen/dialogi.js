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
        <div class="dlg-napit">
          <button type="button" class="dlg-peruuta"></button>
          <button type="button" class="dlg-vahvista"></button>
        </div>
      </div>`;

    document.body.appendChild(peite);
    return peite;
  }

  let peite = null;

  window.vahvista = function (asetukset) {
    if (!peite) peite = luoPeite();

    const o = asetukset || {};
    const laatikko = peite.querySelector(".dlg");
    const nappiOk = peite.querySelector(".dlg-vahvista");
    const nappiEi = peite.querySelector(".dlg-peruuta");

    laatikko.classList.toggle("varoitus", !!o.varoitus);
    peite.querySelector("h3").textContent = o.otsikko || "Vahvista";
    peite.querySelector("p").textContent = o.teksti || "";
    nappiOk.textContent = o.vahvista || "Jatka";
    nappiEi.textContent = o.peruuta || "Peruuta";

    peite.hidden = false;
    nappiOk.focus();

    return new Promise((resolve) => {
      function sulje(tulos) {
        peite.hidden = true;
        nappiOk.removeEventListener("click", ok);
        nappiEi.removeEventListener("click", ei);
        peite.removeEventListener("click", ulkopuolelta);
        document.removeEventListener("keydown", nappain);
        resolve(tulos);
      }

      function ok() { sulje(true); }
      function ei() { sulje(false); }
      function ulkopuolelta(e) { if (e.target === peite) sulje(false); }
      function nappain(e) {
        if (e.key === "Escape") sulje(false);
        if (e.key === "Enter") sulje(true);
      }

      nappiOk.addEventListener("click", ok);
      nappiEi.addEventListener("click", ei);
      peite.addEventListener("click", ulkopuolelta);
      document.addEventListener("keydown", nappain);
    });
  };
})();

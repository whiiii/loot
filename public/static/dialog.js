/**
 * A confirmation dialog to replace the browser's confirm().
 *
 * window.confirmDialog({ title, text, confirm, cancel, warning, input })
 *   -> Promise<boolean>
 *
 * Returns a promise so the call site reads the same as before:
 *   if (!(await confirmDialog({...}))) return;
 *
 * With an `input` option it resolves to the typed text, or null if
 * cancelled — an empty value is never accepted, so the caller does not
 * have to tell "cancelled" apart from "left blank".
 */
(function () {
  function createOverlay() {
    const overlay = document.createElement("div");
    overlay.className = "dlg-overlay";
    overlay.hidden = true;

    overlay.innerHTML = `
      <div class="dlg" role="dialog" aria-modal="true">
        <h3></h3>
        <p></p>
        <input type="text" class="dlg-input" hidden>
        <div class="dlg-error" hidden></div>
        <div class="dlg-buttons">
          <button type="button" class="dlg-cancel"></button>
          <button type="button" class="dlg-confirm"></button>
        </div>
      </div>`;

    document.body.appendChild(overlay);
    return overlay;
  }

  let overlay = null;

  window.confirmDialog = function (options) {
    if (!overlay) overlay = createOverlay();

    const o = options || {};
    const box = overlay.querySelector(".dlg");
    const okButton = overlay.querySelector(".dlg-confirm");
    const cancelButton = overlay.querySelector(".dlg-cancel");
    const input = overlay.querySelector(".dlg-input");
    const error = overlay.querySelector(".dlg-error");

    box.classList.toggle("warning", !!o.warning);
    overlay.querySelector("h3").textContent = o.title || "Vahvista";
    overlay.querySelector("p").textContent = o.text || "";
    okButton.textContent = o.confirm || "Jatka";
    cancelButton.textContent = o.cancel || "Peruuta";

    const asksInput = !!o.input;
    input.hidden = !asksInput;
    error.hidden = true;
    error.textContent = "";

    if (asksInput) {
      input.type = o.input.type || "text";
      input.value = "";
      input.placeholder = o.input.placeholder || "";
    }

    overlay.hidden = false;
    (asksInput ? input : okButton).focus();

    return new Promise((resolve) => {
      function close(result) {
        overlay.hidden = true;
        okButton.removeEventListener("click", accept);
        cancelButton.removeEventListener("click", reject);
        overlay.removeEventListener("click", clickedOutside);
        document.removeEventListener("keydown", keyPressed);
        resolve(result);
      }

      function accept() {
        if (!asksInput) { close(true); return; }

        const value = input.value;
        const min = o.input.min || 0;

        if (value.length < min) {
          error.textContent = o.input.error || `Vähintään ${min} merkkiä.`;
          error.hidden = false;
          input.focus();
          return;
        }
        close(value);
      }

      function reject() { close(asksInput ? null : false); }
      function clickedOutside(e) { if (e.target === overlay) reject(); }
      function keyPressed(e) {
        if (e.key === "Escape") reject();
        if (e.key === "Enter") accept();
      }

      okButton.addEventListener("click", accept);
      cancelButton.addEventListener("click", reject);
      overlay.addEventListener("click", clickedOutside);
      document.addEventListener("keydown", keyPressed);
    });
  };
})();

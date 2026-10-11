/**
 * The top bar's menu.
 *
 * The links are the same and in the same order on every page, and this
 * marks the one you are on. Without the marker the menu looks identical
 * no matter where you are, and finding the right button starts from
 * scratch every time.
 */
(function () {
  // The root redirects to the profile, so it is marked as the same page.
  const path = location.pathname.replace(/\/+$/, "") || "/profile";

  for (const link of document.querySelectorAll(".nav a[href]")) {
    if (link.getAttribute("href") === path) {
      link.classList.add("current");
      link.setAttribute("aria-current", "page");
    }
  }
})();

/**
 * Reveals the officer links.
 *
 * The profile page is the only one a raider can reach, and they must not
 * see links to pages that would turn them away. The page calls this once
 * it knows the role.
 */
window.showOfficerNav = function () {
  for (const el of document.querySelectorAll(".nav [data-officer]")) {
    el.hidden = false;
  }
};

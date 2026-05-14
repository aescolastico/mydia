// Generic "copy to clipboard" hook. Replaces inline onclick handlers
// (forbidden per CLAUDE.md "Never write embedded <script> tags in HEEx").
//
// Usage:
//
//     <button
//       type="button"
//       phx-hook="CopyToClipboard"
//       id="copy-some-thing"
//       data-clipboard-text="literal text to copy"
//     >Copy</button>
//
// Or copy the textContent of another element by selector:
//
//     <button
//       type="button"
//       phx-hook="CopyToClipboard"
//       id="copy-some-block"
//       data-clipboard-source="#some-block"
//     >Copy</button>
const CopyToClipboard = {
  mounted() {
    this.handleClick = (event) => {
      event.preventDefault();
      const text = this.resolveText();
      if (text == null) return;

      navigator.clipboard
        .writeText(text)
        .catch((err) => console.error("CopyToClipboard failed", err));
    };

    this.el.addEventListener("click", this.handleClick);
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  },

  resolveText() {
    const literal = this.el.dataset.clipboardText;
    if (literal != null && literal !== "") return literal;

    const selector = this.el.dataset.clipboardSource;
    if (selector) {
      const node = document.querySelector(selector);
      if (node) return node.innerText;
    }

    return null;
  },
};

export default CopyToClipboard;

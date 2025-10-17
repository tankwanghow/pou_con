// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/pou_con"
import topbar from "../vendor/topbar"
import Keyboard from "../vendor/simple-keyboard.min"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = { ...colocatedHooks }

Hooks.SimpleKeyboard = {
  mounted() {
    const keyboardContainer = document.querySelector(".simple-keyboard");
    const inputElement = this.el;

    // Store original body padding
    this.originalPaddingBottom = document.body.style.paddingBottom || '0px';

    // Initialize the keyboard with mobile-optimized layout
    this.keyboard = new Keyboard({
      mergeDisplay: true,
      layoutName: "default",
      layout: {
        default: [
          'q w e r t y u i o p',
          'a s d f g h j k l',
          '{shift} z x c v b n m',
          '{numbers} , {space} . {bksp}'
        ],
        shift: [
          'Q W E R T Y U I O P',
          'A S D F G H J K L',
          '{shift} Z X C V B N M',
          '{numbers} , {space} . {bksp}'
        ],
        numbers: ["1 2 3", "4 5 6", "7 8 9", "{abc} 0 , . {bksp}"]
      },
      display: {
        "{numbers}": "123",
        "{bksp}": "⌫",
        "{shift}": "⇧",
        "{abc}": "ABC",
      },
      useMouseEvents: true,          // Enable mouse event handling for desktop
      preventMouseDownDefault: true, // Prevent default mousedown to keep input focus
      onChange: input => {
        inputElement.value = input;
        // this.pushEvent("update_input", { value: input });
      },
      onKeyReleased: button => {
        inputElement.focus(); // Refocus input to prevent blur on desktop
      },
      onKeyPress: button => {
        const currentLayout = this.keyboard.options.layoutName;

        // Handle shift toggle
        if (button === '{shift}') {
          const newLayout = currentLayout === 'shift' ? 'default' : 'shift';
          this.keyboard.setOptions({ layoutName: newLayout });
        }

        // Handle layer switches
        if (button === '{numbers}') {
          this.keyboard.setOptions({ layoutName: 'numbers' });
        } else if (button === '{abc}') {
          this.keyboard.setOptions({ layoutName: 'default' });
        }

        // Handle enter or other special keys as needed
        if (button === '{enter}') {
          // Optional: Push event for form submission
          // this.pushEvent("submit_form", {});
        }
      },
      // Additional options as required
    });

    // Show and position keyboard on focus
    inputElement.addEventListener("focus", () => {
      keyboardContainer.style.display = "block";

      // Set fixed positioning at bottom, centered with 50% width
      keyboardContainer.style.position = "fixed";
      keyboardContainer.style.bottom = "0px";
      keyboardContainer.style.width = "50vw";
      keyboardContainer.style.left = "50%";
      keyboardContainer.style.transform = "translateX(-50%)"; // Center horizontally

      // Adjust body padding to prevent overlap
      const keyboardHeight = keyboardContainer.offsetHeight;
      document.body.style.paddingBottom = `${keyboardHeight}px`;

      // Scroll input into view above keyboard
      const viewportHeight = window.innerHeight;
      const inputRect = inputElement.getBoundingClientRect();
      const desiredScroll = window.scrollY + inputRect.top - (viewportHeight - keyboardHeight - 20); // 20px padding for spacing
      window.scrollTo({ top: desiredScroll, behavior: "smooth" });

      this.keyboard.setInput(inputElement.value);
    });

    // Hide keyboard and reset padding on blur
    inputElement.addEventListener("blur", () => {
      keyboardContainer.style.display = "none";
      document.body.style.paddingBottom = this.originalPaddingBottom;
    });

    // Handle server updates
    this.handleEvent("reset_keyboard", () => {
      this.keyboard.setInput("");
    });
  },

  destroyed() {
    if (this.keyboard) {
      this.keyboard.destroy();
    }
    // Reset padding on destruction
    document.body.style.paddingBottom = this.originalPaddingBottom;
  }
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


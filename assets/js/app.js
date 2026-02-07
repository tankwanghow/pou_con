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
import topbar from "../vendor/topbar"
import Keyboard from "../vendor/simple-keyboard.min"

// ============================================
// Theme Management
// ============================================
const THEME_KEY = "pou_con_theme";

function getSystemTheme() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function applyTheme(theme) {
  const resolved = theme === "system" ? getSystemTheme() : theme;
  document.documentElement.setAttribute("data-theme", resolved);
  localStorage.setItem(THEME_KEY, theme);
}

// Apply saved theme immediately (prevent flash)
const savedTheme = localStorage.getItem(THEME_KEY) || "system";
applyTheme(savedTheme);

// Listen for theme toggle events from LiveView
window.addEventListener("phx:set-theme", (e) => {
  applyTheme(e.target.dataset.phxTheme);
});

// Listen for system theme changes when in "system" mode
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  if (localStorage.getItem(THEME_KEY) === "system") {
    applyTheme("system");
  }
});

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

Hooks.FillCurrentTime = {
  mounted() {
    this.el.addEventListener("click", () => {
      const now = new Date();

      // Format date as YYYY-MM-DD
      const year = now.getFullYear();
      const month = String(now.getMonth() + 1).padStart(2, '0');
      const day = String(now.getDate()).padStart(2, '0');
      const dateStr = `${year}-${month}-${day}`;

      // Format time as HH:MM:SS
      const hours = String(now.getHours()).padStart(2, '0');
      const minutes = String(now.getMinutes()).padStart(2, '0');
      const seconds = String(now.getSeconds()).padStart(2, '0');
      const timeStr = `${hours}:${minutes}:${seconds}`;

      // Find the date and time input fields in the form
      const form = this.el.closest('form');
      const dateInput = form.querySelector('input[type="date"]');
      const timeInput = form.querySelector('input[type="time"]');

      if (dateInput) dateInput.value = dateStr;
      if (timeInput) timeInput.value = timeStr;

      // Dispatch change events to ensure LiveView sees the changes
      if (dateInput) dateInput.dispatchEvent(new Event('input', { bubbles: true }));
      if (timeInput) timeInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
  }
};


Hooks.SimpleKeyboard = {
  mounted() {
    const keyboardContainer = document.querySelector(".simple-keyboard");
    const inputElement = this.el;

    // Ensure unique inputName (use id if available, otherwise generate)
    this.inputName = inputElement.id || `input_${Object.keys(window.keyboardInputs || {}).length}`;

    // Store original body padding
    this.originalPaddingBottom = document.body.style.paddingBottom || '0px';

    // Create single keyboard instance if it does not exist
    if (!window.keyboard) {
      window.keyboard = new Keyboard({
        mergeDisplay: true,
        layoutName: "default",
        layout: {
          default: [
            '1 2 3 4 5 6 7 8 9 0 - =',
            'q w e r t y u i o p [ ]',
            'a s d f g h j k l ; \'',
            '{shift} z x c v b n m , .',
            '{tab} {space} {enter} {bksp}'
          ],
          shift: [
            '! @ # $ % ^ & * ( ) _ +',
            'Q W E R T Y U I O P { }',
            'A S D F G H J K L : "',
            '{shift} Z X C V B N M < > ?',
            '{tab} {space} {enter} {bksp}'
          ]
        },
        display: {
          "{bksp}": "⌫",
          "{shift}": "⇧",
          "{tab}": "Tab ⇥",
          "{enter}": "↵"
        },
        useMouseEvents: true,          // Enable mouse event handling for desktop
        preventMouseDownDefault: true, // Prevent default mousedown to keep input focus
        onChange: input => {
          const activeEl = window.keyboardInputs[window.keyboard.options.inputName];
          if (activeEl) {
            activeEl.value = input;
            // Dispatch input event to trigger LiveView's phx-change handler
            activeEl.dispatchEvent(new Event('input', { bubbles: true }));
          }
        },
        onKeyReleased: button => {
          const activeEl = window.keyboardInputs[window.keyboard.options.inputName];
          if (activeEl) activeEl.focus(); // Refocus active input to prevent blur on desktop
        },
        onKeyPress: button => {
          const currentLayout = window.keyboard.options.layoutName;

          // Handle shift toggle
          if (button === '{shift}') {
            const newLayout = currentLayout === 'shift' ? 'default' : 'shift';
            window.keyboard.setOptions({ layoutName: newLayout });
          }

          // Handle layer switches
          if (button === '{numbers}') {
            window.keyboard.setOptions({ layoutName: 'numbers' });
          } else if (button === '{abc}') {
            window.keyboard.setOptions({ layoutName: 'default' });
          }

          // Handle enter key - insert newline for textareas, submit for other inputs
          if (button === '{enter}') {
            const activeEl = window.keyboardInputs[window.keyboard.options.inputName];
            if (activeEl && activeEl.tagName === 'TEXTAREA') {
              const start = activeEl.selectionStart;
              const end = activeEl.selectionEnd;
              const val = activeEl.value;
              activeEl.value = val.substring(0, start) + '\n' + val.substring(end);
              activeEl.selectionStart = activeEl.selectionEnd = start + 1;
              window.keyboard.setInput(activeEl.value);
              activeEl.dispatchEvent(new Event('input', { bubbles: true }));
            } else if (activeEl) {
              const form = activeEl.closest('form');
              if (form) form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
            }
          }

          // Handle tab key - move to next focusable input
          if (button === '{tab}') {
            const activeEl = window.keyboardInputs[window.keyboard.options.inputName];
            if (activeEl) {
              // Get all focusable inputs with SimpleKeyboard hook
              const allInputs = Array.from(document.querySelectorAll('[phx-hook="SimpleKeyboard"]'));
              const currentIndex = allInputs.indexOf(activeEl);
              const nextIndex = (currentIndex + 1) % allInputs.length;
              const nextInput = allInputs[nextIndex];
              if (nextInput) {
                nextInput.focus();
              }
            }
          }
        },
        // Additional options as required
      });

      window.keyboardInputs = {}; // Map of inputName to elements
    }

    // Register this input
    window.keyboardInputs[this.inputName] = inputElement;

    // Sync input changes to keyboard (e.g., from physical keyboard or server updates)
    inputElement.addEventListener('input', event => {
      window.keyboard.setInput(event.target.value);
    });

    // Show and bind keyboard on focus
    inputElement.addEventListener("focus", () => {
      // Set current inputName and sync value
      window.keyboard.setOptions({ inputName: this.inputName });
      window.keyboard.setInput(inputElement.value);

      // Only auto-show in "auto" mode (always_show is handled globally, always_hide stays hidden)
      if (window.keyboardMode === "auto" && keyboardContainer.style.display !== "block") {
        showKeyboard(keyboardContainer);
      }

      // Scroll input into view above keyboard (if keyboard is visible)
      if (keyboardContainer.style.display === "block") {
        const viewportHeight = window.innerHeight;
        const inputRect = inputElement.getBoundingClientRect();
        const desiredScroll = window.scrollY + inputRect.top - (viewportHeight - keyboardContainer.offsetHeight - 20);
        window.scrollTo({ top: desiredScroll, behavior: "smooth" });
      }
    });

    // Hide keyboard on blur only in "auto" mode
    inputElement.addEventListener("blur", event => {
      // Only auto-hide in "auto" mode
      if (window.keyboardMode !== "auto") return;

      const relatedTarget = event.relatedTarget;
      if (relatedTarget && (relatedTarget.closest('.simple-keyboard') || relatedTarget.getAttribute('phx-hook') === 'SimpleKeyboard')) {
        return; // Do not hide if switching to another input or interacting with keyboard
      }

      hideKeyboard(keyboardContainer);
    });

    // Handle server updates
    this.handleEvent("reset_keyboard", () => {
      window.keyboard.setInput("");
    });
  },

  destroyed() {
    // Remove this input from the map
    if (window.keyboardInputs) {
      delete window.keyboardInputs[this.inputName];
    }

    // If no inputs remain, destroy keyboard and reset padding
    if (window.keyboard && Object.keys(window.keyboardInputs).length === 0) {
      window.keyboard.destroy();
      window.keyboard = null;
      window.keyboardInputs = null;
      document.body.style.paddingBottom = this.originalPaddingBottom;
    }
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

// Handle go-back event from LiveView to navigate back in browser history
window.addEventListener("phx:go-back", _event => history.back())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Keyboard mode management: "auto" | "always_show" | "always_hide"
window.keyboardMode = localStorage.getItem("keyboardMode") || "auto";

// ============================================
// Sidebar State Persistence
// ============================================
const SIDEBAR_KEY = "pou_con_sidebar_open";

function initSidebar() {
  const sidebar = document.getElementById("sidebar");
  const overlay = document.getElementById("sidebar-overlay");
  if (!sidebar || !overlay) return;

  // Restore sidebar state from localStorage
  if (localStorage.getItem(SIDEBAR_KEY) === "true") {
    sidebar.classList.remove("-translate-x-full");
    overlay.classList.remove("hidden");
  }
}

function openSidebar() {
  const sidebar = document.getElementById("sidebar");
  const overlay = document.getElementById("sidebar-overlay");
  if (!sidebar || !overlay) return;

  sidebar.classList.remove("-translate-x-full");
  overlay.classList.remove("hidden");
  localStorage.setItem(SIDEBAR_KEY, "true");
}

function closeSidebar() {
  const sidebar = document.getElementById("sidebar");
  const overlay = document.getElementById("sidebar-overlay");
  if (!sidebar || !overlay) return;

  sidebar.classList.add("-translate-x-full");
  overlay.classList.add("hidden");
  localStorage.setItem(SIDEBAR_KEY, "false");
}

// Initialize sidebar on page load and LiveView navigation
document.addEventListener("DOMContentLoaded", initSidebar);
window.addEventListener("phx:page-loading-stop", initSidebar);

// Watch for LiveView DOM patches that reset the sidebar
const sidebarObserver = new MutationObserver((mutations) => {
  if (localStorage.getItem(SIDEBAR_KEY) !== "true") return;

  for (const mutation of mutations) {
    if (mutation.type === "attributes" && mutation.attributeName === "class") {
      const sidebar = document.getElementById("sidebar");
      if (sidebar && sidebar.classList.contains("-translate-x-full")) {
        // LiveView reset the sidebar - restore it
        initSidebar();
      }
    }
  }
});

// Start observing once DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  const sidebar = document.getElementById("sidebar");
  if (sidebar) {
    sidebarObserver.observe(sidebar, { attributes: true, attributeFilter: ["class"] });
  }
});

// Expose functions globally for onclick handlers
window.openSidebar = openSidebar;
window.closeSidebar = closeSidebar;

function setKeyboardMode(mode) {
  window.keyboardMode = mode;
  localStorage.setItem("keyboardMode", mode);

  const keyboardContainer = document.querySelector(".simple-keyboard");
  const toggleBtn = document.getElementById("keyboard-toggle");

  if (!keyboardContainer) return;

  // Update button appearance
  if (toggleBtn) {
    const labels = { auto: "A", always_show: "S", always_hide: "H" };
    const colors = { auto: "bg-blue-600 hover:bg-blue-700", always_show: "bg-green-600 hover:bg-green-700", always_hide: "bg-gray-600 hover:bg-gray-700" };
    const titles = { auto: "Auto (click to change)", always_show: "Always Show (click to change)", always_hide: "Always Hide (click to change)" };

    toggleBtn.textContent = `⌨${labels[mode]}`;
    toggleBtn.title = titles[mode];
    toggleBtn.className = `fixed bottom-4 right-4 z-50 w-14 h-12 ${colors[mode]} text-white rounded-full shadow-lg flex items-center justify-center text-lg font-bold transition-colors`;
  }

  // Apply mode
  if (mode === "always_show") {
    showKeyboard(keyboardContainer);
  } else if (mode === "always_hide") {
    hideKeyboard(keyboardContainer);
  }
  // "auto" mode is handled by focus/blur events
}

function showKeyboard(keyboardContainer) {
  keyboardContainer.style.display = "block";
  keyboardContainer.style.position = "fixed";
  keyboardContainer.style.bottom = "0px";
  keyboardContainer.style.width = "50vw";
  keyboardContainer.style.left = "50%";
  keyboardContainer.style.transform = "translateX(-50%)";

  const keyboardHeight = keyboardContainer.offsetHeight;
  document.body.style.paddingBottom = `${keyboardHeight}px`;
}

function hideKeyboard(keyboardContainer) {
  keyboardContainer.style.display = "none";
  document.body.style.paddingBottom = "0px";
}

// Keyboard toggle button - cycles through modes
document.addEventListener("DOMContentLoaded", () => {
  const toggleBtn = document.getElementById("keyboard-toggle");

  if (toggleBtn) {
    // Initialize display
    setKeyboardMode(window.keyboardMode);

    toggleBtn.addEventListener("click", () => {
      // Cycle: auto -> always_show -> always_hide -> auto
      const modes = ["auto", "always_show", "always_hide"];
      const currentIndex = modes.indexOf(window.keyboardMode);
      const nextMode = modes[(currentIndex + 1) % modes.length];
      setKeyboardMode(nextMode);
    });
  }
});

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


// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

import { initializeDashboard } from "./netmon/dashboard"
document.addEventListener("turbo:load", initializeDashboard)

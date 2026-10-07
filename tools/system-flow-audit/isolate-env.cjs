// Test-only preload: prevent production .env credentials from entering tests.
require('dotenv').config = () => ({ parsed: {} });

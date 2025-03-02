#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

// Network credentials for AP mode
const char* ssid = "SmartSwitch";
const char* password = "switch1234";
IPAddress staticIP(192, 168, 4, 1);
IPAddress gateway(192, 168, 4, 1);
IPAddress subnet(255, 255, 255, 0);

// Web server port
ESP8266WebServer server(80);

// GPIO pin configuration
const int relayPin = 2; // GPIO2 on ESP-01
const int pirPin = 0;   // GPIO0 on ESP-01 for PIR sensor

// State variables
bool relayState = false;
bool autoMode = false;
bool pirDetected = false;
unsigned long lastPirDetection = 0;
const unsigned long AUTO_OFF_DELAY = 60000; // 60 seconds delay before turning off light when no motion

void handleRoot();
void handleToggle();
void handleStatus();
void handleSetMode();
void handleNotFound();

void setup() {
  Serial.begin(115200);
  delay(10);
  
  // Initialize pins
  pinMode(relayPin, OUTPUT);
  pinMode(pirPin, INPUT);
  digitalWrite(relayPin, LOW); // Ensure relay starts in OFF state
  
  // Configure access point with static IP
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(staticIP, gateway, subnet);
  WiFi.softAP(ssid, password);
  
  Serial.println();
  Serial.print("Access Point \"");
  Serial.print(ssid);
  Serial.println("\" started");
  Serial.print("IP address: ");
  Serial.println(WiFi.softAPIP());
  
  // Set up web server routes
  server.on("/", handleRoot);
  server.on("/toggle", handleToggle);
  server.on("/status", handleStatus);
  server.on("/setmode", handleSetMode);
  server.onNotFound(handleNotFound);
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  server.handleClient();
  
  // Handle PIR sensor logic when in auto mode
  if (autoMode) {
    int pirState = digitalRead(pirPin);
    
    if (pirState == HIGH) {
      pirDetected = true;
      lastPirDetection = millis();
      
      // Turn on relay if it's off
      if (!relayState) {
        relayState = true;
        digitalWrite(relayPin, HIGH);
        Serial.println("Motion detected - Turning ON");
      }
    } else if (pirDetected && (millis() - lastPirDetection > AUTO_OFF_DELAY)) {
      // Turn off relay after delay if no motion is detected
      pirDetected = false;
      relayState = false;
      digitalWrite(relayPin, LOW);
      Serial.println("No motion for delay period - Turning OFF");
    }
  }
  
  delay(10);
}

// Handle root URL
void handleRoot() {
  String html = "<html><head>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
  html += "<style>body {font-family: Arial; text-align: center; margin-top: 50px;}";
  html += "button {background-color: #4CAF50; border: none; color: white; padding: 15px 32px;";
  html += "text-align: center; font-size: 16px; margin: 4px 2px; cursor: pointer; border-radius: 10px;}</style>";
  html += "</head><body>";
  html += "<h1>ESP01 Smart Switch</h1>";
  html += "<p>Current state: " + String(relayState ? "ON" : "OFF") + "</p>";
  html += "<p>Mode: " + String(autoMode ? "Automatic (PIR)" : "Manual") + "</p>";
  html += "<button onclick='location.href=\"/toggle\"'>Toggle Switch</button><br><br>";
  html += "<button onclick='location.href=\"/setmode?auto=true\"' style='background-color:" + String(autoMode ? "#2196F3" : "#9E9E9E") + "'>Auto Mode</button> ";
  html += "<button onclick='location.href=\"/setmode?auto=false\"' style='background-color:" + String(!autoMode ? "#2196F3" : "#9E9E9E") + "'>Manual Mode</button>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

// Handle toggle request (only works in manual mode)
void handleToggle() {
  if (!autoMode) {
    relayState = !relayState;
    digitalWrite(relayPin, relayState ? HIGH : LOW);
  }
  server.sendHeader("Location", "/");
  server.send(302, "text/plain", "");
}

// Handle mode setting
void handleSetMode() {
  if (server.hasArg("auto")) {
    String autoArg = server.arg("auto");
    
    if (autoArg == "true") {
      autoMode = true;
      // Reset PIR state when entering auto mode
      pirDetected = false;
    } else if (autoArg == "false") {
      autoMode = false;
      // Turn off relay when exiting auto mode
      relayState = false;
      digitalWrite(relayPin, LOW);
    }
  }
  
  server.sendHeader("Location", "/");
  server.send(302, "text/plain", "");
}

// Handle status request (for API)
void handleStatus() {
  String json = "{\"state\":" + String(relayState ? "true" : "false");
  json += ", \"auto\":" + String(autoMode ? "true" : "false");
  json += ", \"pir\":" + String(pirDetected ? "true" : "false") + "}";
  server.send(200, "application/json", json);
}

// Handle 404
void handleNotFound() {
  server.send(404, "text/plain", "Not found");
}
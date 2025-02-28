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

// GPIO pin connected to relay
const int relayPin = 2; // GPIO2 on ESP-01
bool relayState = false;


void handleRoot();
void handleToggle();
void handleStatus();
void handleNotFound();

void setup() {
  Serial.begin(115200);
  delay(10);
  
  // Initialize relay pin as output
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, HIGH); // Ensure relay starts in OFF state
  
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
  server.onNotFound(handleNotFound);
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
  digitalWrite(relayPin, LOW); // Ensure relay starts in OFF state

}

void loop() {
  server.handleClient();
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
  html += "<button onclick='location.href=\"/toggle\"'>Toggle Switch</button>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

// Handle toggle request
void handleToggle() {
  relayState = !relayState;
  digitalWrite(relayPin, relayState ? HIGH : LOW);
  server.sendHeader("Location", "/");
  server.send(302, "text/plain", "");
}

// Handle status request (for API)
void handleStatus() {
  String json = "{\"state\":" + String(relayState ? "true" : "false") + "}";
  server.send(200, "application/json", json);
}

// Handle 404
void handleNotFound() {
  server.send(404, "text/plain", "Not found");
}
#include <WiFi.h>
#include <WiFiAP.h>
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <EEPROM.h>
#include <HTTPClient.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>

// Pin definitions
#define DHT_PIN 4        // DHT11 sensor connected to D4
#define BUTTON1_PIN 26   // Button 1 connected to D26 (Mode)
#define BUTTON2_PIN 27   // Button 2 connected to D27 (Up)
#define BUTTON3_PIN 25   // Button 3 connected to D25 (Down)
#define ALARM_PIN 23     // Alarm connected to D23
#define SMOKE_SENSOR_PIN 33  // MQ gas sensor connected to D33
#define RELAY_PIN 16     // Relay module connected to D16

// Constants
#define EEPROM_SIZE 512
#define AP_SSID_PREFIX "Smart Gas Monitor"
#define AP_PASSWORD "12345678"  // Default password, will be changed during setup
#define MAX_DEVICES 10
#define LCD_COLS 16
#define LCD_ROWS 4
#define LCD_ADDR 0x27  // I2C address for LCD (may vary)

// DHT sensor
#define DHTTYPE DHT11
DHT dht(DHT_PIN, DHTTYPE);

// LCD Display
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

// Web server and WebSocket
AsyncWebServer server(80);
WebSocketsServer webSocket = WebSocketsServer(81);

// Variables
float temperature = 0;
float humidity = 0;
float gasLevel = 0;
bool alarmActive = false;
bool relayState = false;
bool autoMode = true;
float gasThreshold = 500;  // Default gas threshold (adjust based on sensor)
float tempThreshold = 35;  // Default temperature threshold in °C

// Button states
bool menuButtonState = false;
bool button2State = false;
bool button3State = false;
bool menuButtonLastState = false;
bool button2LastState = false;
bool button3LastState = false;
unsigned long lastButtonDebounceTime = 0;
unsigned long debounceDelay = 50;

// Menu system
enum MenuState {
  MAIN_SCREEN,
  MENU_MAIN,
  SET_TEMP_THRESHOLD,
  SET_GAS_THRESHOLD,
  WIFI_SETTINGS,
  DEVICE_INFO
};

MenuState currentMenu = MAIN_SCREEN;
int menuPosition = 0;
const int MAX_MENU_ITEMS = 4;

// Network settings
String apSSID;
String apPassword = AP_PASSWORD;
String stationSSID = "";
String stationPassword = "";
bool apMode = true;
bool configMode = false;
String deviceID;

// EEPROM addresses
const int ADDR_AP_PASS = 0;
const int ADDR_STATION_SSID = 32;
const int ADDR_STATION_PASS = 64;
const int ADDR_GAS_THRESHOLD = 128;
const int ADDR_TEMP_THRESHOLD = 132;
const int ADDR_AUTO_MODE = 136;

// Function prototypes
void handleWebSocketMessage(uint8_t num, WStype_t type, uint8_t * payload, size_t length);
void sendSensorData();
void updateLCD();
void checkAlarms();
void saveSettings();
void loadSettings();
void setupAccessPoint();
void setupStation();
void handleButtons();
void navigateMenu();

void setup() {
  // Initialize Serial communication
  Serial.begin(115200);
  Serial.println("Starting Smart Gas and Temperature Monitor System");
  
  // Initialize pins
  pinMode(BUTTON1_PIN, INPUT_PULLUP);
  pinMode(BUTTON2_PIN, INPUT_PULLUP);
  pinMode(BUTTON3_PIN, INPUT_PULLUP);
  pinMode(ALARM_PIN, OUTPUT);
  pinMode(RELAY_PIN, OUTPUT);
  
  digitalWrite(ALARM_PIN, LOW);
  digitalWrite(RELAY_PIN, LOW);
  
  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  
  // Load settings from EEPROM
  loadSettings();
  
  // Initialize LCD
  Wire.begin();
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Initializing...");
  
  // Initialize DHT sensor
  dht.begin();
  
  // Generate unique device ID based on MAC address
  uint8_t mac[6];
  WiFi.macAddress(mac);
  deviceID = String(mac[0], HEX) + String(mac[1], HEX) + String(mac[2], HEX) + 
             String(mac[3], HEX) + String(mac[4], HEX) + String(mac[5], HEX);
  deviceID.toUpperCase();
  
  apSSID = AP_SSID_PREFIX;
  
  // Setup network
  if (stationSSID.length() > 0) {
    setupStation();
    setupAccessPoint();
    // If station connection fails, fall back to AP mode
    if (WiFi.status() != WL_CONNECTED) {
      setupAccessPoint();
    }
  } else {
    setupAccessPoint();

  }
  
  // Setup WebSocket server
  webSocket.begin();
  webSocket.onEvent(handleWebSocketMessage);
  
  // Setup HTTP server routes
  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    String html = "<html><head>";
    html += "<title>Smart Gas Monitor</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
    html += "<style>body{font-family:Arial;text-align:center;margin:0;padding:20px;}</style>";
    html += "</head><body>";
    html += "<h1>Smart Gas and Temperature Monitor</h1>";
    html += "<p>Use the mobile app for full functionality.</p>";
    html += "<p>Device ID: " + deviceID + "</p>";
    html += "<p>IP Address: " + WiFi.localIP().toString() + "</p>";
    html += "</body></html>";
    request->send(200, "text/html", html);
  });
  
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    DynamicJsonDocument doc(1024);
    doc["temperature"] = temperature;
    doc["humidity"] = humidity;
    doc["gasLevel"] = gasLevel;
    doc["alarmActive"] = alarmActive;
    doc["relayState"] = relayState;
    doc["autoMode"] = autoMode;
    doc["gasThreshold"] = gasThreshold;
    doc["tempThreshold"] = tempThreshold;
    doc["deviceID"] = deviceID;
    
    String response;
    serializeJson(doc, response);
    request->send(200, "application/json", response);
  });
  
  server.on("/api/control", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (request->hasParam("relay", true)) {
      String value = request->getParam("relay", true)->value();
      relayState = (value == "1" || value == "true" || value == "on");
      digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
    }
    
    if (request->hasParam("auto", true)) {
      String value = request->getParam("auto", true)->value();
      autoMode = (value == "1" || value == "true" || value == "on");
      EEPROM.write(ADDR_AUTO_MODE, autoMode);
      EEPROM.commit();
    }
    
    if (request->hasParam("gasThreshold", true)) {
      gasThreshold = request->getParam("gasThreshold", true)->value().toFloat();
      EEPROM.writeFloat(ADDR_GAS_THRESHOLD, gasThreshold);
      EEPROM.commit();
    }
    
    if (request->hasParam("tempThreshold", true)) {
      tempThreshold = request->getParam("tempThreshold", true)->value().toFloat();
      EEPROM.writeFloat(ADDR_TEMP_THRESHOLD, tempThreshold);
      EEPROM.commit();
    }
    
    request->send(200, "application/json", "{\"status\":\"ok\"}");
  });
  
  server.begin();
  
  // Display ready message
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Ready");
  lcd.setCursor(0, 1);
  if (apMode) {
    lcd.print("AP: " + apSSID);
  } else {
    lcd.print("WiFi: Connected");
  }
  delay(2000);
}

void loop() {
  // Handle WebSocket communications
  webSocket.loop();
  
  // Read sensors (every 2 seconds)
  static unsigned long lastSensorRead = 0;
  if (millis() - lastSensorRead > 2000) {
    lastSensorRead = millis();
    
    // Read temperature and humidity
    float newTemperature = dht.readTemperature();
    float newHumidity = dht.readHumidity();
    
    // Only update if readings are valid
    if (!isnan(newTemperature) && !isnan(newHumidity)) {
      temperature = newTemperature;
      humidity = newHumidity;
    }
    
    // Read gas sensor
    gasLevel = analogRead(SMOKE_SENSOR_PIN);
    
    // Check alarm conditions
    checkAlarms();
    
    // Update LCD
    updateLCD();
    
    // Send updated data to connected clients
    sendSensorData();
  }
  
  // Handle button presses for menu navigation
  handleButtons();
}

void handleWebSocketMessage(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  switch(type) {
    case WStype_DISCONNECTED:
      Serial.printf("[%u] Disconnected!\n", num);
      break;
    case WStype_CONNECTED:
      {
        IPAddress ip = webSocket.remoteIP(num);
        Serial.printf("[%u] Connected from %d.%d.%d.%d\n", num, ip[0], ip[1], ip[2], ip[3]);
        
        // Send current status to newly connected client
        sendSensorData();
      }
      break;
    case WStype_TEXT:
      {
        String message = String((char*)payload);
        Serial.printf("[%u] Received text: %s\n", num, message.c_str());
        
        DynamicJsonDocument doc(1024);
        DeserializationError error = deserializeJson(doc, message);
        
        if (!error) {
          if (doc.containsKey("command")) {
            String command = doc["command"];
            
            if (command == "getStatus") {
              sendSensorData();
            }
            else if (command == "setRelay") {
              if (doc.containsKey("state")) {
                relayState = doc["state"];
                digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
                sendSensorData();
              }
            }
            else if (command == "setAutoMode") {
              if (doc.containsKey("state")) {
                autoMode = doc["state"];
                EEPROM.write(ADDR_AUTO_MODE, autoMode);
                EEPROM.commit();
                sendSensorData();
              }
            }
            else if (command == "setThresholds") {
              if (doc.containsKey("gas")) {
                gasThreshold = doc["gas"];
                EEPROM.writeFloat(ADDR_GAS_THRESHOLD, gasThreshold);
              }
              if (doc.containsKey("temp")) {
                tempThreshold = doc["temp"];
                EEPROM.writeFloat(ADDR_TEMP_THRESHOLD, tempThreshold);
              }
              EEPROM.commit();
              sendSensorData();
            }
            else if (command == "reset") {
              if (doc.containsKey("alarm") && doc["alarm"]) {
                alarmActive = false;
                digitalWrite(ALARM_PIN, LOW);
                sendSensorData();
              }
            }
          }
        }
      }
      break;
  }
}

void sendSensorData() {
  DynamicJsonDocument doc(1024);
  doc["deviceID"] = deviceID;
  doc["temperature"] = temperature;
  doc["humidity"] = humidity;
  doc["gasLevel"] = gasLevel;
  doc["alarmActive"] = alarmActive;
  doc["relayState"] = relayState;
  doc["autoMode"] = autoMode;
  doc["gasThreshold"] = gasThreshold;
  doc["tempThreshold"] = tempThreshold;
  
  String message;
  serializeJson(doc, message);
  webSocket.broadcastTXT(message);
}

void updateLCD() {
  if (currentMenu == MAIN_SCREEN) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Temp: ");
    lcd.print(temperature, 1);
    lcd.print((char)223);
    lcd.print("C");
    
    lcd.setCursor(0, 1);
    lcd.print("Humidity: ");
    lcd.print(humidity, 1);
    lcd.print("%");
    
    lcd.setCursor(0, 2);
    lcd.print("Gas Level: ");
    lcd.print(gasLevel, 0);
    
    lcd.setCursor(0, 3);
    if (alarmActive) {
      lcd.print("ALARM ACTIVE!");
    } else {
      lcd.print("Status: Normal");
    }
  }
}

void checkAlarms() {
  bool shouldAlarm = false;
  
  // Check gas level threshold
  if (gasLevel > gasThreshold) {
    shouldAlarm = true;
  }
  
  // Check temperature threshold
  if (temperature > tempThreshold) {
    shouldAlarm = true;
  }
  
  // Set alarm state
  if (shouldAlarm && !alarmActive) {
    alarmActive = true;
    digitalWrite(ALARM_PIN, HIGH);
    
    // In auto mode, also activate the relay (e.g., to turn on exhaust fan)
    if (autoMode) {
      relayState = true;
      digitalWrite(RELAY_PIN, HIGH);
    }
  } 
  // Note: We don't automatically turn off the alarm - it requires manual reset
}

void saveSettings() {
  // Save AP password (if changed)
  for (int i = 0; i < apPassword.length(); i++) {
    EEPROM.write(ADDR_AP_PASS + i, apPassword[i]);
  }
  EEPROM.write(ADDR_AP_PASS + apPassword.length(), 0); // Null terminator
  
  // Save station SSID (if set)
  for (int i = 0; i < stationSSID.length(); i++) {
    EEPROM.write(ADDR_STATION_SSID + i, stationSSID[i]);
  }
  EEPROM.write(ADDR_STATION_SSID + stationSSID.length(), 0); // Null terminator
  
  // Save station password (if set)
  for (int i = 0; i < stationPassword.length(); i++) {
    EEPROM.write(ADDR_STATION_PASS + i, stationPassword[i]);
  }
  EEPROM.write(ADDR_STATION_PASS + stationPassword.length(), 0); // Null terminator
  
  // Save thresholds
  EEPROM.writeFloat(ADDR_GAS_THRESHOLD, gasThreshold);
  EEPROM.writeFloat(ADDR_TEMP_THRESHOLD, tempThreshold);
  
  // Save auto mode setting
  EEPROM.write(ADDR_AUTO_MODE, autoMode ? 1 : 0);
  
  // Commit changes
  EEPROM.commit();
}

void loadSettings() {
  // Load AP password
  apPassword = "";
  for (int i = 0; i < 32; i++) {
    char c = EEPROM.read(ADDR_AP_PASS + i);
    if (c == 0) break;
    apPassword += c;
  }
  if (apPassword.length() == 0) {
    apPassword = AP_PASSWORD;
  }
  
  // Load station SSID
  stationSSID = "";
  for (int i = 0; i < 32; i++) {
    char c = EEPROM.read(ADDR_STATION_SSID + i);
    if (c == 0) break;
    stationSSID += c;
  }
  
  // Load station password
  stationPassword = "";
  for (int i = 0; i < 32; i++) {
    char c = EEPROM.read(ADDR_STATION_PASS + i);
    if (c == 0) break;
    stationPassword += c;
  }
  
  // Load thresholds
  gasThreshold = EEPROM.readFloat(ADDR_GAS_THRESHOLD);
  if (isnan(gasThreshold) || gasThreshold < 0 || gasThreshold > 4095) {
    gasThreshold = 500; // Default if invalid
  }
  
  tempThreshold = EEPROM.readFloat(ADDR_TEMP_THRESHOLD);
  if (isnan(tempThreshold) || tempThreshold < 0 || tempThreshold > 100) {
    tempThreshold = 35; // Default if invalid
  }
  
  // Load auto mode setting
  autoMode = EEPROM.read(ADDR_AUTO_MODE) == 1;
}

void setupAccessPoint() {
  Serial.println("Setting up Access Point...");
  WiFi.softAP(apSSID.c_str(), apPassword.c_str());
  
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.print(apPassword.c_str());
  Serial.println(IP);
  apMode = true;
}

// void setupStation() {
//   Serial.println("Connecting to WiFi network...");
//   WiFi.begin(stationSSID.c_str(), stationPassword.c_str());
  
//   // Wait for connection with timeout
//   int timeout = 0;
//   while (WiFi.status() != WL_CONNECTED && timeout < 20) {
//     delay(500);
//     Serial.print(".");
//     timeout++;
//   }
  
//   if (WiFi.status() == WL_CONNECTED) {
//     Serial.println("");
//     Serial.print("Connected to ");
//     Serial.println(stationSSID);
//     Serial.print("IP address: ");
//     Serial.println(WiFi.localIP());
//     apMode = false;
//   } else {
//     Serial.println("");
//     Serial.println("Connection failed");
//   }
// }


void setupStation() {
  Serial.println("Connecting to WiFi network...");
  
  // CHANGE: Set up AP mode first to ensure it's always active
  WiFi.softAP(apSSID.c_str(), apPassword.c_str());
  Serial.print("AP IP address: ");
  Serial.println(WiFi.softAPIP());
  
  // Then connect to the WiFi network
  WiFi.mode(WIFI_AP_STA); // CHANGE: Set mode to both AP and Station
  WiFi.begin(stationSSID.c_str(), stationPassword.c_str());
  
  // Wait for connection with timeout
  int timeout = 0;
  while (WiFi.status() != WL_CONNECTED && timeout < 20) {
    delay(500);
    Serial.print(".");
    timeout++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("");
    Serial.print("Connected to ");
    Serial.println(stationSSID);
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
    apMode = false; // Still mark as station mode for the UI
  } else {
    Serial.println("");
    Serial.println("Connection failed");
  }
}
void handleButtons() {
  // Read button states with debounce
  bool menuButton = digitalRead(BUTTON1_PIN) == LOW;
  bool b2 = digitalRead(BUTTON2_PIN) == LOW;
  bool b3 = digitalRead(BUTTON3_PIN) == LOW;
  
  if (menuButton != menuButtonLastState || b2 != button2LastState || b3 != button3LastState) {
    lastButtonDebounceTime = millis();
  }
  
  if ((millis() - lastButtonDebounceTime) > debounceDelay) {
    // If button state has changed, update the state
    if (menuButton != menuButtonState) {
      menuButtonState = menuButton;
      if (menuButtonState) {
        // Button 1 (Mode) pressed
        if (currentMenu == MAIN_SCREEN) {
          currentMenu = MENU_MAIN;
          menuPosition = 0;
          navigateMenu();
        } else {
          currentMenu = MAIN_SCREEN;
          updateLCD();
        }
      }
    }
    
    if (b2 != button2State) {
      button2State = b2;
      if (button2State ) {

        if(currentMenu == SET_TEMP_THRESHOLD) {
          // Button 2 (Up) pressed
          tempThreshold += 1;
          navigateMenu();
        } else if(currentMenu == SET_GAS_THRESHOLD) {
          // Button 2 (Up) pressed
          gasThreshold += 10;
          navigateMenu();
        }else if (currentMenu == WIFI_SETTINGS) {
          apMode = !apMode;
          if (apMode) {
            setupAccessPoint();
          } else {
            setupStation();
        }
       
          
        }
        else if( currentMenu == MENU_MAIN){
        // Button 2 (Up) pressed
        menuPosition = (menuPosition - 1 + MAX_MENU_ITEMS) % MAX_MENU_ITEMS;
        navigateMenu();}
      }
    }
    
    if (b3 != button3State) {
      button3State = b3;
      if (button3State && currentMenu != MAIN_SCREEN) {
        // Button 3 (Down/Select) pressed
        if (currentMenu == MENU_MAIN) {
          // Enter selected submenu
          switch(menuPosition) {
            case 0: // Temperature Threshold
              currentMenu = SET_TEMP_THRESHOLD;
              break;
            case 1: // Gas Threshold
              currentMenu = SET_GAS_THRESHOLD;
              break;
            case 2: // WiFi Settings
              currentMenu = WIFI_SETTINGS;
              break;
            case 3: // Device Info
              currentMenu = DEVICE_INFO;
              break;
          }
        }else if (currentMenu == SET_TEMP_THRESHOLD) {
          // Button 3 (Down/Select) pressed
          gasThreshold -= 10;
         
          
          
        }else if (currentMenu == SET_GAS_THRESHOLD) {
          // Button 3 (Down/Select) pressed
          tempThreshold -= 1;
         

          
          
        }else if (currentMenu == WIFI_SETTINGS) {
          // Button 3 (Down/Select) pressed
          apMode = !apMode;
          if (apMode) {
            setupAccessPoint();
          } else {
            setupStation();
          }
         

          
          
          
        }
        
        else {
          // Navigate within submenu
          menuPosition = (menuPosition + 1) % MAX_MENU_ITEMS;
        }
        navigateMenu();
      }
    }
  }
  
  menuButtonLastState = menuButton;
  button2LastState = b2;
  button3LastState = b3;
}

void navigateMenu() {
  lcd.clear();
  
  switch (currentMenu) {
    case MENU_MAIN:
      lcd.setCursor(0, 0);
      lcd.print("MENU:");
      lcd.setCursor(0, 1);
      lcd.print(menuPosition == 0 ? "> " : "  ");
      lcd.print("Temperature");
      lcd.setCursor(0, 2);
      lcd.print(menuPosition == 1 ? "> " : "  ");
      lcd.print("Gas Level");
      lcd.setCursor(0, 3);
      lcd.print(menuPosition == 2 ? "> " : "  ");
      lcd.print("WiFi Settings");
      break;
      
    case SET_TEMP_THRESHOLD:
      lcd.setCursor(0, 0);
      lcd.print("Temp. Thresh");
      lcd.setCursor(0, 1);
      lcd.print("Curr: ");
      lcd.print(tempThreshold, 1);
      lcd.print((char)223);
      lcd.print("C");
      lcd.setCursor(0, 2);
      lcd.print("UP: +1  DOWN: -1");
      lcd.setCursor(0, 3);
      lcd.print("MODE: Back to Menu");
      break;
      
    case SET_GAS_THRESHOLD:
      lcd.setCursor(0, 0);
      lcd.print("Gas Thresh");
      lcd.setCursor(0, 1);
      lcd.print("Curr: ");
      lcd.print(gasThreshold, 0);
      lcd.setCursor(0, 2);
      lcd.print("UP: +10  DOWN: -10");
      lcd.setCursor(0, 3);
      lcd.print("MODE: Back to Menu");
      break;
      
    case WIFI_SETTINGS:
      lcd.setCursor(0, 0);
      lcd.print("WiFi Settings");
      lcd.setCursor(0, 1);
      if (apMode) {
        lcd.print("Mode: AP");
      } else {
        lcd.print("Mode: Station");
      }
      lcd.setCursor(0, 2);
      lcd.print("SSID: ");
      lcd.print(apMode ? apSSID : stationSSID);
      lcd.setCursor(0, 3);
      lcd.print("MODE: Back to Menu");
      break;
      
    case DEVICE_INFO:
      lcd.setCursor(0, 0);
      lcd.print("Device Information");
      lcd.setCursor(0, 1);
      lcd.print("ID: ");
      lcd.print(deviceID.substring(0, 10));
      lcd.setCursor(0, 2);
      lcd.print("IP: ");
      lcd.print(apMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString());
      lcd.setCursor(0, 3);
      lcd.print("MODE: Back to Menu");
      break;
      
    default:
      updateLCD();
      break;
  }
}
# 🧠 MONIX SCRAM ULTRA+ 
## Phase 1: Context Engine Implementation Guide

---

## 📋 Overview

The **Context Engine** is the foundation of MONIX SCRAM Ultra+. It replaces simple reactive detection ("malware detected → kill process") with intelligent behavioral memory.

### Key Innovation
Instead of analyzing isolated events, Context Engine maintains:
- **Complete process history** (behavior patterns, network connections, file operations)
- **Dynamic reputation** (safe → unknown → suspicious → hostile)
- **Risk scoring** (0.0 safe to 1.0 threat) based on multiple factors
- **Pattern recognition** (detects APT-like attack chains)

---

## 🏗 Architecture

### 1. ProcessContext Struct
Each tracked process has a full behavioral profile:

```cpp
struct ProcessContext {
  // Identity
  DWORD processId;
  std::wstring processName;
  std::wstring imagePath;
  
  // Reputation (0.0 - 1.0)
  ProcessReputation reputation;  // safe→unknown→suspicious→hostile
  float riskScore;               // Weighted multi-factor model
  
  // Timeline
  uint64_t firstSeen;
  uint64_t lastActivity;
  
  // Behavior flags (32-bit bitmask)
  uint32_t behaviorFlags;  // C2Communication | PrivilegeEscalation | etc
  
  // History
  std::vector<std::wstring> recentConnections;
  std::vector<std::wstring> dnsQueries;
  std::vector<std::wstring> filesCreated;
  std::vector<std::wstring> filesModified;
  
  // Counters
  int suspiciousEventCount;
  int threatEventCount;
};
```

### 2. BehaviorFlag Enum (32 behavior types)
- Network: PortScanning, C2Communication, DNSExfiltration
- File: MassFileCreation, ExecutableCreation, EncryptionActivity
- Registry: PersistenceWrite, RunKeyModification, ServiceModification
- Process: PrivilegeEscalation, ParentProcessInjection, ObfuscatedCode
- Evasion: AntivirusDisable, DefenderDisable, RegistryObfuscation

### 3. Reputation States
```
Safe       → Process is trusted (Microsoft-signed)
Unknown    → First time seeing this process
Suspicious → Red flags detected (1-2 behavior flags)
Hostile    → Confirmed threat (3+ behaviors OR attack patterns)
```

### 4. Risk Scoring Formula
```
Risk = w1*behavior_risk + w2*anomaly_risk + w3*history_risk

where:
  w1 = 0.4  (behavior patterns weight)
  w2 = 0.3  (anomaly detection weight)
  w3 = 0.3  (historical events weight)

Behavior risk includes:
  - Each C2Communication flag: +0.25
  - PrivilegeEscalation: +0.30
  - AntivirusDisable: +0.40
  - EncryptionActivity: +0.25
  - etc...
```

### 5. Built-in Attack Patterns (Detectable Now)
```
1. C2 Beacon Pattern
   → Repeated connections to same IP + Port Scanning
   → Confidence: 0.9

2. Ransomware Pattern
   → MassFileCreation + EncryptionActivity + PersistenceWrite
   → Confidence: 1.0

3. Privilege Escalation
   → PrivilegeEscalation + AntivirusDisable
   → Confidence: 0.95

4. Data Exfiltration
   → DNSExfiltration + C2Communication
   → Confidence: 0.85

5. Persistence Mechanism
   → PersistenceWrite + RunKeyModification + ServiceModification
   → Confidence: 0.80
```

---

## 🔧 Integration with Monix

### Step 1: Add to AppState (in main.cpp)
```cpp
struct AppState {
  // ... existing fields ...
  
  // New: Context Engine instance
  std::unique_ptr<ContextEngine> contextEngine;
  
  // Statistics display
  int trackedProcesses = 0;
  int suspiciousProcesses = 0;
  int hostileProcesses = 0;
};
```

### Step 2: Initialize Context Engine (in main initialization)
```cpp
void InitializeMonix() {
  // ... existing init ...
  
  // Initialize Context Engine
  appState.contextEngine = std::make_unique<ContextEngine>();
  std::wstring dataPath = GetMonixDataFolder();
  appState.contextEngine->Initialize(dataPath);
}
```

### Step 3: Hook Process Monitoring (in scanning loop)
```cpp
void UpdateProcessContext() {
  // Get all running processes
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(PROCESSENTRY32W);
  
  if (Process32FirstW(snapshot, &entry)) {
    do {
      // Get or create context for this process
      auto ctx = appState.contextEngine->GetOrCreateContext(
        entry.th32ProcessID,
        entry.szExeFile
      );
      
      // Check process status and record behaviors
      // (implemented in Phase 2 with ETW)
      
    } while (Process32NextW(snapshot, &entry));
  }
  
  CloseHandle(snapshot);
  
  // Update statistics for UI
  appState.trackedProcesses = appState.contextEngine->GetTotalProcessesTracked();
  appState.suspiciousProcesses = appState.contextEngine->GetSuspiciousCount();
  appState.hostileProcesses = appState.contextEngine->GetHostileCount();
}
```

### Step 4: Record Behaviors (called from detectors)
```cpp
// When detecting suspicious behavior:
appState.contextEngine->RecordBehavior(
  processId,
  BehaviorFlag::C2Communication
);

// When seeing network connection:
appState.contextEngine->RecordNetworkConnection(
  processId,
  L"192.168.1.100:4444"
);

// When monitoring file operations:
appState.contextEngine->RecordFileOperation(
  processId,
  L"C:\\Users\\victim\\encrypted.txt",
  L"create"
);
```

### Step 5: Query for Threats (before SCRAM activation)
```cpp
// Get all hostile processes
auto hostileProcesses = appState.contextEngine->GetHighRiskProcesses();

for (const auto& ctx : hostileProcesses) {
  // Log the threat
  LogThreatDetection(ctx->processId, ctx->riskScore, ctx->processName);
  
  // If risk >= 0.85, consider SCRAM activation
  if (ctx->riskScore >= 0.85f) {
    TriggerScramMode();
  }
}
```

---

## 📊 UI Integration (for tabs/display)

### New Antivirus Tab: "Process Reputation"
```
═══════════════════════════════════════════════════════════
  PROCESS REPUTATION MONITOR      Safe: 127  Suspicious: 3  Hostile: 1
═══════════════════════════════════════════════════════════

[HOSTILE] svchost.exe (PID: 4821)
├─ Reputation: HOSTILE
├─ Risk Score: 0.92
├─ Behaviors: C2Communication | PrivilegeEscalation | AntivirusDisable
├─ Patterns: C2 Beacon (0.9) + Privilege Escalation (0.95)
├─ Network: 192.168.1.1:4444 (repeated 47 times)
├─ Timeline: First Seen: 2026-06-10 14:23:15 | Last Activity: 2026-06-10 14:24:01
└─ Action: [QUARANTINE] [KILL] [SCRAM]

[SUSPICIOUS] powershell.exe (PID: 3224)
├─ Reputation: SUSPICIOUS
├─ Risk Score: 0.68
├─ Behaviors: ExecutableCreation | PersistenceWrite
├─ DNS Queries: malicious-c2.ru, backup-payload.xyz
└─ Action: [MONITOR] [ANALYZE] [ISOLATE]

[SAFE] explorer.exe (PID: 2108)
├─ Reputation: SAFE
├─ Risk Score: 0.0
├─ Status: Microsoft-signed, no suspicious activity
└─ Status: Protected ✓
```

---

## 🔄 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      MONIX SCRAM ULTRA+                         │
└─────────────────────────────────────────────────────────────────┘

[PHASE 1: SENSOR LAYER - Detect]
    ↓
    Process.GetProcesses() → Network Monitoring → File I/O
    ↓
    [EVENT STREAM]
    ├── Process Created: explorer.exe (PID 2108)
    ├── Network: svchost.exe → 192.168.1.1:4444
    ├── File: powershell.exe creates "payload.exe"
    └── Registry: svchost.exe writes Run key
    
    ↓
    
[PHASE 1: CONTEXT ENGINE - Analyze]
    ├── GetOrCreateContext(4821, "svchost.exe")
    │   └── reputation = UNKNOWN (first time)
    │
    ├── RecordBehavior(4821, BehaviorFlag::C2Communication)
    │   └── ctx->behaviorFlags |= C2Communication
    │
    ├── RecordNetworkConnection(4821, "192.168.1.1:4444")
    │   └── ctx->recentConnections.push_back(...)
    │
    ├── CalculateReputation(4821)
    │   ├── Check: threatEventCount >= 3? No
    │   ├── Check: suspiciousEventCount >= 5? No
    │   ├── Check: behaviorFlags > 0? YES → SUSPICIOUS
    │   └── reputation = SUSPICIOUS
    │
    ├── CalculateRiskScore(4821)
    │   ├── BehaviorRisk(C2Communication) = 0.25 × 0.4 = 0.10
    │   ├── AnomalyRisk(networks...) = 0.10 × 0.3 = 0.03
    │   ├── HistoryRisk(events...) = 0.10 × 0.3 = 0.03
    │   └── Total Risk = 0.16
    │
    └── DetectPatterns(4821)
        └── "C2 Beacon Pattern" NOT matched yet (need more evidence)
    
    ↓
    
[CONTEXT TRACKING: Persistence]
    └── SaveContextsToFile()
        └── process_contexts.json
            ├── PID, reputation, riskScore
            ├── behaviorFlags, timestamps
            ├── network connections
            └── threat event history

    ↓
    
[PHASE 2-11: SENSOR LAYER + ADVANCED DETECTION]
    ├── ETW Events reveal more C2 connections
    ├── RecordBehavior(4821, BehaviorFlag::PrivilegeEscalation)
    ├── RecordBehavior(4821, BehaviorFlag::AntivirusDisable)
    └── CalculateRiskScore(4821) → 0.87 (HOSTILE!)

    ↓
    
[RESPONSE: SCRAM Protocol]
    ├── Risk >= 0.85? YES
    ├── TriggerScramMode()
    ├── Phase 1: Isolate process
    ├── Phase 2: Network disconnect
    ├── Phase 3: Collect forensics
    └── Phase 4: Recovery
```

---

## 💾 Persistence & Recovery

### process_contexts.json Format
```json
[
  {
    "pid": 4821,
    "name": "svchost.exe",
    "path": "C:\\Windows\\System32\\svchost.exe",
    "reputation": 2,
    "riskScore": 0.87,
    "firstSeen": 1717999395,
    "lastActivity": 1718086795,
    "behaviorFlags": 15,
    "suspiciousEventCount": 8,
    "threatEventCount": 2,
    "parentPid": 700,
    "isElevated": true,
    "isSignedByMS": false
  }
]
```

### On Application Start
1. `ContextEngine::Initialize()` loads `process_contexts.json`
2. Historical reputation carries over between sessions
3. Long-running threats become more suspicious with time
4. Allows detection of evolving APT campaigns

---

## 🎯 Next Steps (Phase 2+)

### Phase 2: ETW Sensor Layer
- **What**: Replace basic Process.GetProcesses() with Event Tracing for Windows
- **Why**: Real-time detection BEFORE malware acts, not after
- **How**: Register for ETW providers (Kernel Logger, Security Logger, Application Tracking)
- **Result**: See Process Creation events, Network events, File I/O in real-time

### Phase 3: Attack Graph
- **What**: Build relationship graph (Process→File, Process→Network, etc.)
- **Why**: Detect chained attacks (Word→PowerShell→beacon→persistence)
- **How**: Graph library + pattern matching engine
- **Result**: Find "Word.exe → PowerShell → encoded command → network beacon"

### Phase 4: Multi-Factor Risk Model
- **What**: Advanced weighted formula with configurable parameters
- **Why**: Fine-grained control over threat sensitivity
- **How**: Add machine learning preprocessing of weights
- **Result**: User can say "I want 95% recall" and system adjusts weights

### Phase 5: Adaptive Containment
- **What**: Instead of kill/no-kill, use graduated response
- **Levels**: observe→throttle→isolate_network→suspend→sandbox
- **Why**: Avoid false positives while still stopping threats
- **Result**: Process isolated but not dead, can be analyzed in sandbox

---

## ⚙️ Configuration (Future)

```ini
# monix.ini

[ContextEngine]
PersistenceFile = contexts.json
MaxContextAge = 3600        ; seconds before pruning
SaveInterval = 300          ; auto-save every 5 minutes
MaxNetworkEntries = 100
MaxDNSEntries = 1000

[RiskScoring]
BehaviorWeight = 0.4
AnomalyWeight = 0.3
HistoryWeight = 0.3
C2Weight = 0.25
PrivilegeEscalationWeight = 0.30
AntivirusDisableWeight = 0.40

[AlertThresholds]
SuspiciousThreshold = 0.50
HighRiskThreshold = 0.70
HostileThreshold = 0.85
```

---

## 📈 Expected Improvements

### Before (Reactive)
- ❌ Malware runs → detects signature → kills process
- ❌ 200ms average response time
- ❌ No correlation between events
- ❌ Can't detect novel attacks

### After (Predictive)
- ✅ Behavior anomaly detected → process isolated immediately
- ✅ 50ms average response time
- ✅ Full attack chain visible in graph
- ✅ Detects APT-like patterns even without known malware

---

## 🧪 Testing Context Engine

### Unit Test 1: Basic Reputation Calculation
```cpp
TEST(ContextEngine, ReputationCalculation) {
  auto ctx = engine.GetOrCreateContext(100, L"test.exe");
  
  // Start as Unknown
  EXPECT_EQ(ContextEngine::CalculateReputation(100), ProcessReputation::Unknown);
  
  // Record one suspicious behavior
  engine.RecordBehavior(100, BehaviorFlag::C2Communication);
  auto rep = engine.CalculateReputation(100);
  EXPECT_EQ(rep, ProcessReputation::Suspicious);
  
  // Record threat events
  engine.RecordThreatEvent(100, "Test threat");
  engine.RecordThreatEvent(100, "Test threat");
  engine.RecordThreatEvent(100, "Test threat");
  
  rep = engine.CalculateReputation(100);
  EXPECT_EQ(rep, ProcessReputation::Hostile);
}
```

### Unit Test 2: Pattern Detection
```cpp
TEST(ContextEngine, C2BehaviorPattern) {
  auto ctx = engine.GetOrCreateContext(200, L"malware.exe");
  
  // Record C2 behaviors
  engine.RecordBehavior(200, BehaviorFlag::C2Communication);
  engine.RecordBehavior(200, BehaviorFlag::PortScanning);
  
  // Both flags must be present for C2 Beacon Pattern
  auto patterns = engine.DetectPatterns(200);
  EXPECT_TRUE(patterns.size() > 0);
  EXPECT_EQ(patterns[0].name, L"C2 Beacon Pattern");
}
```

### Unit Test 3: Risk Scoring
```cpp
TEST(ContextEngine, RiskScoring) {
  auto ctx = engine.GetOrCreateContext(300, L"payload.exe");
  
  // Safe process
  float risk = engine.CalculateRiskScore(300);
  EXPECT_NEAR(risk, 0.0f, 0.01f);
  
  // Record behaviors
  engine.RecordBehavior(300, BehaviorFlag::AntivirusDisable);
  engine.RecordBehavior(300, BehaviorFlag::PrivilegeEscalation);
  engine.RecordBehavior(300, BehaviorFlag::PersistenceWrite);
  
  // Risk should be high
  risk = engine.CalculateRiskScore(300);
  EXPECT_GT(risk, 0.70f);
}
```

---

## 📚 Files Created

1. **context_engine.h** (270 lines)
   - Header file with all struct and class definitions
   - ContextEngine API
   - BehaviorFlag enum with 17 behavior types
   - ProcessContext serialization

2. **context_engine.cpp** (500+ lines)
   - Full implementation
   - Reputation calculation algorithms
   - Risk scoring multi-factor model
   - Pattern detection
   - JSON persistence/loading
   - Thread-safe operations

3. **ARCHITECTURE.md** (this file)
   - Complete design documentation
   - Integration guide
   - Data flow diagrams
   - Testing guide

---

## 🔗 Integration Checklist

- [ ] Add `#include "context_engine.h"` to main.cpp
- [ ] Add `std::unique_ptr<ContextEngine> contextEngine;` to AppState
- [ ] Call `contextEngine->Initialize()` in setup
- [ ] Call `UpdateProcessContext()` in main monitoring loop
- [ ] Add "Process Reputation" tab to UI with display of contexts
- [ ] Wire behavior recording calls from antivirus module
- [ ] Add metrics to top status bar (tracked: X, suspicious: Y, hostile: Z)
- [ ] Implement SaveContextsOnShutdown()
- [ ] Test pattern detection with sample behaviors
- [ ] Verify JSON persistence between runs

---

**Next: Phase 2 will add ETW-based real-time event detection to feed events into Context Engine.**

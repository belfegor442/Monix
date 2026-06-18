#include <iostream>
#include <vector>
#include "Monix/Tests/CoreModuleTests.hpp"

using namespace MonixTests;

int main() {
    std::cout << "====== Running Monix Core Module Tests ======\n\n";
    
    auto results = CoreModuleTests::RunAllTests();
    
    int passed = 0;
    int failed = 0;
    
    for (const auto& result : results) {
        if (result.passed) {
            std::cout << "[PASS] " << result.name << "\n";
            passed++;
        } else {
            std::cout << "[FAIL] " << result.name << "\n";
            if (!result.errorMessage.empty()) {
                std::cout << "       Error: " << result.errorMessage << "\n";
            }
            failed++;
        }
    }
    
    std::cout << "\n====== Test Summary ======\n";
    std::cout << "Passed: " << passed << "\n";
    std::cout << "Failed: " << failed << "\n";
    std::cout << "Total:  " << (passed + failed) << "\n";
    
    return failed > 0 ? 1 : 0;
}

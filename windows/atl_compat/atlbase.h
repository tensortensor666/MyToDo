#pragma once

#include <string>
#include <vector>
#include <windows.h>

class CW2A {
 public:
  explicit CW2A(const wchar_t* value, UINT code_page = CP_ACP) {
    if (value == nullptr) {
      return;
    }
    const int size = WideCharToMultiByte(
        code_page, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) {
      return;
    }
    std::vector<char> buffer(static_cast<size_t>(size));
    if (WideCharToMultiByte(code_page, 0, value, -1, buffer.data(), size,
                            nullptr, nullptr) > 0) {
      value_ = buffer.data();
    }
  }

  operator const char*() const { return value_.c_str(); }

 private:
  std::string value_;
};

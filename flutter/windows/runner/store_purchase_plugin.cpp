#include "store_purchase_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// C++/WinRT headers for Windows Store API (requires Windows SDK 10.0.17763+).
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>

#include <memory>
#include <string>

namespace winrt_store = winrt::Windows::Services::Store;

namespace {

// Keep channel alive for the lifetime of the application.
static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_channel;

/// Check if the Pro add-on is purchased via Store license.
winrt::fire_and_forget CheckProPurchased(
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    auto context = winrt_store::StoreContext::GetDefault();
    auto app_license = co_await context.GetAppLicenseAsync();
    auto add_on_licenses = app_license.AddOnLicenses();

    bool purchased = false;
    for (auto const& pair : add_on_licenses) {
      auto license = pair.Value();
      if (license.IsActive()) {
        auto token = std::wstring(license.InAppOfferToken());
        auto sku_id = std::wstring(license.SkuStoreId());
        if (token == L"latera_pro" ||
            sku_id.find(L"latera_pro") != std::wstring::npos) {
          purchased = true;
          break;
        }
      }
    }

    result->Success(flutter::EncodableValue(purchased));
  } catch (winrt::hresult_error const& e) {
    result->Error("STORE_ERROR", winrt::to_string(e.message()));
  } catch (...) {
    result->Error("UNKNOWN_ERROR", "Failed to check Store license");
  }
}

/// Initiate purchase of the Pro add-on via Store dialog.
winrt::fire_and_forget PurchasePro(
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    std::string product_id) {
  try {
    auto context = winrt_store::StoreContext::GetDefault();
    auto wide_id = winrt::to_hstring(product_id);
    auto purchase_result = co_await context.RequestPurchaseAsync(wide_id);

    switch (purchase_result.Status()) {
      case winrt_store::StorePurchaseStatus::Succeeded:
      case winrt_store::StorePurchaseStatus::AlreadyPurchased:
        result->Success(flutter::EncodableValue(std::string("success")));
        break;
      case winrt_store::StorePurchaseStatus::NotPurchased:
        result->Success(flutter::EncodableValue(std::string("cancelled")));
        break;
      default:
        result->Success(flutter::EncodableValue(std::string("error")));
        break;
    }
  } catch (winrt::hresult_error const& e) {
    result->Error("STORE_ERROR", winrt::to_string(e.message()));
  } catch (...) {
    result->Error("UNKNOWN_ERROR", "Failed to purchase from Store");
  }
}

}  // namespace

void RegisterStorePurchasePlugin(flutter::BinaryMessenger* messenger) {
  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.latera.store_purchase",
          &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "isProPurchased") {
          CheckProPurchased(
              std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
                  std::move(result)));
        } else if (call.method_name() == "buyPro") {
          std::string product_id = "latera_pro";
          if (call.arguments() &&
              std::holds_alternative<std::string>(*call.arguments())) {
            product_id = std::get<std::string>(*call.arguments());
          }
          PurchasePro(
              std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
                  std::move(result)),
              product_id);
        } else {
          result->NotImplemented();
        }
      });
}

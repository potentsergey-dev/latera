#ifndef RUNNER_STORE_PURCHASE_PLUGIN_H_
#define RUNNER_STORE_PURCHASE_PLUGIN_H_

namespace flutter {
class BinaryMessenger;
}

/// Register native Windows Store IAP plugin via MethodChannel.
///
/// Uses WinRT Windows.Services.Store.StoreContext to:
/// - Check if the Pro add-on has been purchased.
/// - Launch the Store purchase dialog for the Pro add-on.
///
/// Requires the app to be packaged with MSIX and have an identity.
/// During development (unpackaged), calls return graceful errors.
void RegisterStorePurchasePlugin(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_STORE_PURCHASE_PLUGIN_H_

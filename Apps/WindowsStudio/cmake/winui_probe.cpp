#define UNICODE
#define _UNICODE
#define NOMINMAX
#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#define NTDDI_VERSION 0x0A00000C

#include <windows.h>
#ifdef GetCurrentTime
#undef GetCurrentTime
#endif
#ifdef GetCurrentDirectory
#undef GetCurrentDirectory
#endif
#ifdef GetEnvironmentVariable
#undef GetEnvironmentVariable
#endif
#ifdef SendMessage
#undef SendMessage
#endif
#ifdef GetObject
#undef GetObject
#endif

#include <inspectable.h>
#include <roapi.h>
#include <winstring.h>
#include <windows.foundation.h>
#include <windows.foundation.collections.h>
#include <windows.ui.xaml.h>
#include <windows.ui.xaml.controls.h>
#include <windows.ui.xaml.controls.primitives.h>
#include <windows.ui.xaml.hosting.h>
#include <windows.ui.xaml.hosting.desktopwindowxamlsource.h>
#include <windows.ui.xaml.markup.h>
#include <wrl.h>
#include <wrl/event.h>

#ifdef GetCurrentTime
#undef GetCurrentTime
#endif
#ifdef GetCurrentDirectory
#undef GetCurrentDirectory
#endif
#ifdef GetObject
#undef GetObject
#endif

using ABI::Windows::Foundation::IEventHandler;
using ABI::Windows::Foundation::IPropertyValueStatics;
using ABI::Windows::Foundation::Collections::IObservableVector;
using ABI::Windows::Foundation::Collections::IVector;
using ABI::Windows::UI::Xaml::Controls::IControl;
using ABI::Windows::UI::Xaml::IRoutedEventArgs;
using ABI::Windows::UI::Xaml::IRoutedEventHandler;
using ABI::Windows::UI::Xaml::IUIElement;
using ABI::Windows::UI::Xaml::Controls::IComboBox;
using ABI::Windows::UI::Xaml::Controls::IItemsControl;
using ABI::Windows::UI::Xaml::Controls::Primitives::ISelector;
using ABI::Windows::UI::Xaml::Controls::Primitives::IButtonBase;
using ABI::Windows::UI::Xaml::Controls::Primitives::IToggleButton;
using ABI::Windows::UI::Xaml::IFrameworkElement;
using ABI::Windows::UI::Xaml::Hosting::IDesktopWindowXamlSource;
using ABI::Windows::UI::Xaml::Hosting::IWindowsXamlManager;
using ABI::Windows::UI::Xaml::Hosting::IWindowsXamlManagerStatics;
using ABI::Windows::UI::Xaml::Markup::IXamlReaderStatics;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

int main() {
    ComPtr<IControl> control;
    if (control) {
        control->put_IsEnabled(TRUE);
    }
    ComPtr<IToggleButton> toggle;
    ComPtr<IButtonBase> button;
    auto handler = Callback<IRoutedEventHandler>([](IInspectable*, IRoutedEventArgs*) -> HRESULT {
        return S_OK;
    });
    EventRegistrationToken token{};
    if (toggle) {
        toggle->add_Checked(handler.Get(), &token);
        toggle->add_Unchecked(handler.Get(), &token);
    }
    if (button) {
        button->add_Click(handler.Get(), &token);
    }
    ComPtr<IItemsControl> items;
    ComPtr<IObservableVector<IInspectable*>> vector;
    ComPtr<IVector<IInspectable*>> list;
    if (items) {
        items->get_Items(vector.ReleaseAndGetAddressOf());
    }
    if (vector) {
        vector.As(&list);
    }
    if (list) {
        list->Clear();
        list->Append(nullptr);
    }
    ComPtr<ISelector> selector;
    if (selector) {
        INT32 index = 0;
        selector->get_SelectedIndex(&index);
        selector->put_SelectedIndex(0);
    }
    ComPtr<IComboBox> combo;
    auto opened = Callback<IEventHandler<IInspectable*>>([](IInspectable*, IInspectable*) -> HRESULT {
        return S_OK;
    });
    if (combo) {
        EventRegistrationToken drop{};
        combo->add_DropDownOpened(opened.Get(), &drop);
    }
    ComPtr<IUIElement> element;
    if (element) {
        EventRegistrationToken focus{};
        element->add_GotFocus(handler.Get(), &focus);
    }
    ComPtr<IPropertyValueStatics> props;
    if (props) {
        ComPtr<IInspectable> value;
        props->CreateString(nullptr, value.ReleaseAndGetAddressOf());
    }
    ComPtr<IWindowsXamlManagerStatics> managerStatics;
    ComPtr<IWindowsXamlManager> manager;
    if (managerStatics) {
        managerStatics->InitializeForCurrentThread(manager.ReleaseAndGetAddressOf());
    }
    ComPtr<IXamlReaderStatics> reader;
    if (reader) {
        ComPtr<IInspectable> loaded;
        reader->Load(nullptr, loaded.ReleaseAndGetAddressOf());
    }
    ComPtr<IFrameworkElement> fe;
    if (fe) {
        ComPtr<IInspectable> named;
        fe->FindName(nullptr, named.ReleaseAndGetAddressOf());
    }
    HSTRING factoryName = nullptr;
    ComPtr<IInspectable> factory;
    RoGetActivationFactory(factoryName, IID_PPV_ARGS(&factory));
    ComPtr<IDesktopWindowXamlSource> source;
    ComPtr<::IDesktopWindowXamlSourceNative> native;
    ComPtr<::IDesktopWindowXamlSourceNative2> native2;
    (void)source;
    (void)native;
    MSG msg{};
    BOOL processed = FALSE;
    if (native2) {
        native2->PreTranslateMessage(&msg, &processed);
    }
    return processed ? 1 : 0;
}

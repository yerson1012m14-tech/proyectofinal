#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# XITFORGE 10.0.15 - aplica cambios al túnel.
# Ejecutar desde la raíz de yerson1012m14-tech/proyectofinal.

from pathlib import Path
import re
import shutil

ROOT = Path.cwd()
FILES = {
    "installer": ROOT / "XitForge-Tunnel/module/XFAirLiftInstaller.m",
    "view": ROOT / "XitForge-Tunnel/module/XFAirLiftViewController.m",
    "build_module": ROOT / "XitForge-Tunnel/module/build-module.sh",
    "workflow": ROOT / ".github/workflows/build.yml",
}

def fail(msg):
    raise SystemExit(f"\nERROR: {msg}\n")

def read(path):
    if not path.is_file():
        fail(f"No existe: {path}")
    return path.read_text(encoding="utf-8")

def backup(path):
    bak = path.with_suffix(path.suffix + ".bak")
    shutil.copy2(path, bak)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        fail(f"{label}: se esperaba 1 coincidencia y se encontraron {count}.")
    return text.replace(old, new, 1)

def regex_replace_once(text, pattern, repl, label, flags=0):
    out, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        fail(f"{label}: no se encontró el bloque esperado.")
    return out

# 1) TÚNEL SEGUNDO, AJUSTES TERCERO
path = FILES["installer"]
text = read(path)
old = '''    NSMutableArray<UIViewController *> *updated = [existing mutableCopy];
    [updated addObject:navigation];
    [tabController setViewControllers:updated animated:NO];
'''
new = '''    NSMutableArray<UIViewController *> *updated = [existing mutableCopy];

    // Orden final: Inicio · Túnel · Ajustes.
    NSUInteger tunnelIndex = MIN((NSUInteger)1, updated.count);
    [updated insertObject:navigation atIndex:tunnelIndex];

    [tabController setViewControllers:updated animated:NO];
'''
text = replace_once(text, old, new, "Orden de pestañas")
backup(path)
path.write_text(text, encoding="utf-8")

# 2) UI PROFESIONAL + ROJO + SIN CATÁLOGO + NOTIFICACIONES
path = FILES["view"]
text = read(path)

text = replace_once(
    text,
    '#import <QuickLook/QuickLook.h>\n',
    '#import <QuickLook/QuickLook.h>\n#import <UserNotifications/UserNotifications.h>\n',
    "Import UserNotifications"
)

anchor = '''    return label;
}

@interface XFConnectionStatusView : UIStackView
'''
insert = '''    return label;
}

static UIColor *XFBrandRed(void) {
    return [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
}

static UIColor *XFBrandRedSoft(void) {
    return [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:0.16];
}

static UIColor *XFPanelBackground(void) {
    return [UIColor colorWithRed:0.055 green:0.025 blue:0.028 alpha:1.0];
}

static UIColor *XFScreenBackground(void) {
    return [UIColor colorWithRed:0.018 green:0.012 blue:0.014 alpha:1.0];
}

@interface XFConnectionStatusView : UIStackView
'''
text = replace_once(text, anchor, insert, "Colores XITFORGE")

old = '''        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.layer.cornerRadius = 12;
'''
new = '''        self.backgroundColor = XFPanelBackground();
        self.layer.cornerRadius = 18;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [XFBrandRed() colorWithAlphaComponent:0.34].CGColor;
        self.layer.shadowColor = XFBrandRed().CGColor;
        self.layer.shadowOpacity = 0.10;
        self.layer.shadowRadius = 14;
        self.layer.shadowOffset = CGSizeMake(0, 5);
'''
text = replace_once(text, old, new, "Tarjeta de estado")

text = replace_once(
    text,
    '    self.tunnelLabel.textColor = connected ? UIColor.systemGreenColor : UIColor.systemRedColor;\n',
    '    self.tunnelLabel.textColor = connected ? XFBrandRed() : UIColor.systemGrayColor;\n',
    "Color estado túnel"
)
text = replace_once(
    text,
    '    self.pairingLabel.textColor = inProgress || !available ? UIColor.systemOrangeColor : UIColor.systemGreenColor;\n',
    '    self.pairingLabel.textColor = inProgress ? UIColor.systemOrangeColor : (available ? XFBrandRed() : UIColor.systemGrayColor);\n',
    "Color pairing"
)

old_method = '''- (UIButton *)buttonWithTitle:(NSString *)title selector:(SEL)selector prominent:(BOOL)prominent {
    UIButtonConfiguration *configuration = prominent ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 14, 12, 14);
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}
'''
new_method = '''- (UIButton *)buttonWithTitle:(NSString *)title selector:(SEL)selector prominent:(BOOL)prominent {
    UIButtonConfiguration *configuration = prominent ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(13, 16, 13, 16);
    configuration.baseForegroundColor = prominent ? UIColor.whiteColor : XFBrandRed();
    configuration.baseBackgroundColor = prominent ? XFBrandRed() : XFBrandRedSoft();

    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 14;
    button.layer.borderWidth = prominent ? 0.0 : 1.0;
    button.layer.borderColor = [XFBrandRed() colorWithAlphaComponent:0.32].CGColor;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}
'''
text = replace_once(text, old_method, new_method, "Botones")

text = replace_once(
    text,
    '''- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
''',
    '''- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.backgroundColor = XFScreenBackground();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UINavigationBarAppearance *navigationAppearance = [[UINavigationBarAppearance alloc] init];
    [navigationAppearance configureWithOpaqueBackground];
    navigationAppearance.backgroundColor = UIColor.blackColor;
    navigationAppearance.shadowColor = [XFBrandRed() colorWithAlphaComponent:0.18];
    navigationAppearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: XFBrandRed(),
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]
    };
    self.navigationController.navigationBar.standardAppearance = navigationAppearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = navigationAppearance;
    self.navigationController.navigationBar.compactAppearance = navigationAppearance;
    self.navigationController.navigationBar.tintColor = XFBrandRed();
''',
    "Apariencia navegación"
)

text = replace_once(
    text,
    '[self.headerStack addArrangedSubview:XFLabel(@"Archivos por túnel", UIFontTextStyleTitle2, UIColor.labelColor)];',
    '''UILabel *heroTitle = XFLabel(@"XITFORGE TÚNEL", UIFontTextStyleTitle2, XFBrandRed());
    heroTitle.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
    heroTitle.textAlignment = NSTextAlignmentCenter;
    [self.headerStack addArrangedSubview:heroTitle];''',
    "Título profesional"
)

text = replace_once(
    text,
    '[self.headerStack addArrangedSubview:XFLabel(@"1. Con el Wi-Fi encendido, empareja este iPhone o importa su registro.\\n2. Activa LocalDevVPN.\\n3. Conecta para consultar el catálogo de apps.", UIFontTextStyleSubheadline, UIColor.secondaryLabelColor)];',
    '[self.headerStack addArrangedSubview:XFLabel(@"1. Con el Wi-Fi encendido, empareja este iPhone o importa su registro.\\n2. Activa LocalDevVPN.\\n3. Pulsa Conectar túnel para comprobar la conexión.", UIFontTextStyleSubheadline, UIColor.lightGrayColor)];',
    "Guía"
)

text = replace_once(
    text,
    '    self.pairingPINLabel = XFLabel(@"", UIFontTextStyleTitle1, UIColor.labelColor);\n',
    '    self.pairingPINLabel = XFLabel(@"", UIFontTextStyleTitle1, UIColor.whiteColor);\n',
    "Color PIN"
)

text = replace_once(
    text,
    '    self.connectButton = [self buttonWithTitle:@"Conectar y cargar apps" selector:@selector(connectAndLoad) prominent:YES];\n',
    '    self.connectButton = [self buttonWithTitle:@"Conectar túnel" selector:@selector(connectAndLoad) prominent:YES];\n',
    "Botón conectar"
)

search_block = '''    self.appSearch = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.appSearch.searchResultsUpdater = self;
    self.appSearch.obscuresBackgroundDuringPresentation = NO;
    self.appSearch.searchBar.placeholder = @"Buscar app o identificador";
    self.navigationItem.searchController = self.appSearch;
    self.definesPresentationContext = YES;
'''
text = replace_once(
    text,
    search_block,
    '''    // Catálogo oculto en esta interfaz.
    self.navigationItem.searchController = nil;
    self.definesPresentationContext = YES;
''',
    "Ocultar buscador"
)

for old_text, new_text in {
    'Pulsa «Conectar y cargar apps» para comprobar el túnel de nuevo.':
        'Pulsa «Conectar túnel» para comprobar el túnel de nuevo.',
    'Emparejamiento guardado. Activa LocalDevVPN y pulsa «Conectar y cargar apps».':
        'Emparejamiento guardado. Activa LocalDevVPN y pulsa «Conectar túnel».',
    'Dirección guardada. Pulsa «Conectar y cargar apps» para comprobarla.':
        'Dirección guardada. Pulsa «Conectar túnel» para comprobarla.',
    'Vuelve a XitForge con el Wi-Fi encendido y pulsa «Conectar y cargar apps».':
        'Vuelve a XitForge con el Wi-Fi encendido y pulsa «Conectar túnel».',
}.items():
    if old_text not in text:
        fail(f"No se encontró texto esperado: {old_text}")
    text = text.replace(old_text, new_text)

notif_methods = '''- (void)requestPairingNotificationPermission {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                                 UNAuthorizationOptionSound |
                                                 UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *error) {
            (void)granted;
            (void)error;
        }];
    }];
}

- (void)sendPairingPINNotification:(NSString *)PIN {
    if (PIN.length != 6) return;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        UNAuthorizationStatus status = settings.authorizationStatus;
        BOOL allowed = status == UNAuthorizationStatusAuthorized ||
                       status == UNAuthorizationStatusProvisional ||
                       status == UNAuthorizationStatusEphemeral;
        if (!allowed) return;

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = @"XITFORGE · CÓDIGO DE EMPAREJAMIENTO";
        content.body = [NSString stringWithFormat:@"Tu código es %@. Introdúcelo en Ajustes para completar el emparejamiento.", PIN];
        content.sound = UNNotificationSound.defaultSound;
        content.threadIdentifier = @"com.xitforge.pairing";

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.25 repeats:NO];
        NSString *identifier =
            [NSString stringWithFormat:@"xitforge-pairing-%@", NSUUID.UUID.UUIDString];
        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];

        [center addNotificationRequest:request withCompletionHandler:nil];
    }];
}

- (void)startOnDevicePairing {
'''
text = replace_once(text, '- (void)startOnDevicePairing {\n', notif_methods, "Notificaciones")

old = '''    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
        XFPresentError(self, @"Se requiere iOS 27", @"Esta forma de emparejar necesita iOS 27 y su opción de emparejamiento en Modo de desarrollador. Puedes seguir usando «Importar emparejamiento» con un registro válido.");
        return;
    }
    self.busy = YES;
'''
new = '''    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
        XFPresentError(self, @"Se requiere iOS 27", @"Esta forma de emparejar necesita iOS 27 y su opción de emparejamiento en Modo de desarrollador. Puedes seguir usando «Importar emparejamiento» con un registro válido.");
        return;
    }

    [self requestPairingNotificationPermission];
    self.busy = YES;
'''
text = replace_once(text, old, new, "Permiso notificaciones")

old = '''        self.pairingGuideLabel.text = @"Introduce este PIN en Ajustes > Privacidad y seguridad > Modo de desarrollador > Emparejar con XitForge. El proceso seguirá activo mientras cambias de app.";
        [self.view setNeedsLayout];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"PIN de emparejamiento disponible");
'''
new = '''        self.pairingGuideLabel.text = @"Introduce este PIN en Ajustes > Privacidad y seguridad > Modo de desarrollador > Emparejar con XitForge. El proceso seguirá activo mientras cambias de app.";
        [self.view setNeedsLayout];
        [self sendPairingPINNotification:PIN];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"PIN de emparejamiento disponible");
'''
text = replace_once(text, old, new, "Enviar PIN por notificación")

pattern = r'''- \(void\)connectAndLoad \{\n.*?\n\}\n\n- \(void\)updateSearchResultsForSearchController:'''
replacement = '''- (void)connectAndLoad {
    if (self.busy) { [self.refreshControl endRefreshing]; return; }
    if (!self.pairingAvailable) {
        [self.refreshControl endRefreshing];
        XFPresentError(self, @"Emparejamiento necesario", @"Empareja primero este iPhone o importa su registro de emparejamiento.");
        return;
    }

    self.busy = YES;
    self.statusLabel.text = @"Comprobando el túnel y los servicios…";
    [self updateButtons];
    [self.connectionStatus showConnecting];

    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        BOOL connected = [self.backend connectWithError:&error];
        connected = self.backend.connected;
        BOOL fileAccess = self.backend.applicationFileAccessAvailable;
        NSString *capabilities = self.backend.fileAccessSummary;
        NSString *recoveryWarning = connected ? self.backend.lastDirectoryWarning : @"";

        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.tunnelConnected = connected;
            self.applicationFileAccessAvailable = fileAccess;
            self.capabilitiesText = capabilities;
            self.recoveryWarning = recoveryWarning;
            self.applications = @[];
            self.visibleApplications = @[];

            if (!connected) {
                self.statusLabel.text = @"Conexión no establecida. Comprueba LocalDevVPN, Wi-Fi y el emparejamiento.";
                XFPresentError(self, @"No se pudo conectar", XFErrorMessage(error));
            } else {
                self.statusLabel.text = fileAccess
                    ? @"Túnel conectado correctamente. Servicios de archivos disponibles."
                    : @"Túnel conectado correctamente.";
            }

            if (connected && recoveryWarning.length) {
                self.statusLabel.text =
                    [self.statusLabel.text stringByAppendingFormat:@"\\n\\n%@", recoveryWarning];
            }

            [self.tableView reloadData];
            [self updateButtons];
            [self.view setNeedsLayout];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
        });
    });
}

- (void)updateSearchResultsForSearchController:'''
text = regex_replace_once(text, pattern, replacement, "Conectar sin catálogo", flags=re.S)

text = replace_once(
    text,
    '- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApplications.count; }\n- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Catálogo de apps"; }\n',
    '- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 0; }\n- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return nil; }\n',
    "Ocultar catálogo"
)

footer_pattern = r'''- \(NSString \*\)tableView:\(UITableView \*\)tableView titleForFooterInSection:\(NSInteger\)section \{\n.*?\n\}\n\n- \(UITableViewCell \*\)tableView:'''
footer_repl = '''- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *version = XFString([[NSBundle mainBundle] objectForInfoDictionaryKey:@"XFTunnelModuleVersion"]);
    NSString *summary = [NSString stringWithFormat:@"Módulo %@ · %@\\nConexión y emparejamiento administrados por XITFORGE.",
        version.length ? version : @"1.3.1",
        self.capabilitiesText ?: @"Conexión pendiente"];
    return self.recoveryWarning.length
        ? [NSString stringWithFormat:@"%@\\n%@", summary, self.recoveryWarning]
        : summary;
}

- (UITableViewCell *)tableView:'''
text = regex_replace_once(text, footer_pattern, footer_repl, "Pie profesional", flags=re.S)

backup(path)
path.write_text(text, encoding="utf-8")

# 3) LINK UserNotifications
path = FILES["build_module"]
text = read(path)
old = '-framework QuickLook -framework AVFoundation -framework Security'
new = '-framework QuickLook -framework AVFoundation -framework UserNotifications -framework Security'
if old not in text:
    fail("No se encontró la lista de frameworks en build-module.sh")
text = text.replace(old, new, 1)
backup(path)
path.write_text(text, encoding="utf-8")

# 4) WORKFLOW: COMPILAR EL MÓDULO ACTUAL
path = FILES["workflow"]
text = read(path)

text = replace_once(
    text,
    '''      - name: Agregar módulo XitForge 1.3.1
        run: |
          python3 XitForge-Tunnel/tools/verify_delivery.py
          python3 - <<'PY'
''',
    '''      - name: Compilar e integrar módulo XitForge 1.3.1
        run: |
          bash XitForge-Tunnel/module/build-module.sh
          python3 - <<'PY'
''',
    "Workflow"
)

text = replace_once(
    text,
    "'XitForge-Tunnel/prebuilt/XFAirLift.dylib',",
    "'XitForge-Tunnel/module/build/XFAirLift.dylib',",
    "Dylib compilada"
)

backup(path)
path.write_text(text, encoding="utf-8")

print("\nCAMBIOS APLICADOS CORRECTAMENTE\n")
for p in FILES.values():
    print("OK ", p.relative_to(ROOT))
print("\nInicio 1.º · Túnel 2.º · Ajustes 3.º")
print("Catálogo oculto · UI roja/negra · PIN por notificación")
print("GitHub Actions recompilará el módulo actualizado.")

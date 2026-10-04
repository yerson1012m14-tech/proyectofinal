#import "XFFileCreationProbeController.h"
#import "XFAirLiftBackend.h"
#import "XFFileCreationProbe.h"

static NSString *const XFProbeRecordKey=@"XitForge.FileCreationProbe.Active.v1";
static UILabel *XFProbeLabel(NSString *text, UIFontTextStyle style) {
    UILabel *label=[UILabel new];label.text=text;label.font=[UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory=YES;label.numberOfLines=0;label.textColor=UIColor.labelColor;return label;
}
@interface XFFileCreationProbeController ()
@property(nonatomic,strong) XFAirLiftBackend *backend;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,strong) UITextField *applicationField;
@property(nonatomic,strong) UITextField *folderField;
@property(nonatomic,strong) UIButton *createButton;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,strong) UIButton *reportCopyButton;
@property(nonatomic,strong) UILabel *reportLabel;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,copy) NSDictionary *record;
@property(nonatomic,copy) NSString *report;
@property(nonatomic,assign) BOOL busy;
@end
@implementation XFFileCreationProbeController
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend queue:(dispatch_queue_t)queue {
    if((self=[super init])){_backend=backend;_queue=queue;self.title=@"Prueba de creación";}
    return self;
}
- (UIButton *)button:(NSString *)title selector:(SEL)selector primary:(BOOL)primary {
    UIButtonConfiguration *config=primary?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;
    config.title=title;config.contentInsets=NSDirectionalEdgeInsetsMake(14,14,14,14);
    UIButton *button=[UIButton buttonWithConfiguration:config primaryAction:nil];
    button.titleLabel.numberOfLines=0;button.titleLabel.adjustsFontForContentSizeCategory=YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];return button;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *field=[UITextField new];field.placeholder=placeholder;field.borderStyle=UITextBorderStyleRoundedRect;
    field.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];field.adjustsFontForContentSizeCategory=YES;
    field.autocorrectionType=UITextAutocorrectionTypeNo;field.autocapitalizationType=UITextAutocapitalizationTypeNone;
    field.spellCheckingType=UITextSpellCheckingTypeNo;field.clearButtonMode=UITextFieldViewModeWhileEditing;
    field.keyboardType=UIKeyboardTypeASCIICapable;[field.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;self.view.tintColor=UIColor.systemRedColor;
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;[self.view addSubview:scroll];
    self.applicationField=[self field:@"com.ejemplo.app"];self.applicationField.accessibilityLabel=@"Identificador de la app";
    self.folderField=[self field:@"Documents"];self.folderField.text=@"Documents";self.folderField.accessibilityLabel=@"Carpeta existente, relativa al contenedor";
    self.createButton=[self button:@"Crear archivo de prueba" selector:@selector(confirmCreate) primary:YES];
    self.deleteButton=[self button:@"Comprobar y eliminar prueba" selector:@selector(confirmDelete) primary:NO];
    self.reportCopyButton=[self button:@"Copiar resultado" selector:@selector(copyReport) primary:NO];
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.spinner.hidesWhenStopped=YES;
    self.reportLabel=XFProbeLabel(@"La prueba aún no se ha ejecutado.",UIFontTextStyleFootnote);
    self.reportLabel.accessibilityTraits=UIAccessibilityTraitUpdatesFrequently;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[
        XFProbeLabel(@"¿Puede crear archivos?",UIFontTextStyleTitle2),
        XFProbeLabel(@"Crearemos un texto pequeño con un nombre único en una carpeta existente y comprobaremos su contenido leyendo la misma ruta. Cierra la app de destino antes de empezar.",UIFontTextStyleSubheadline),
        XFProbeLabel(@"Aplicación",UIFontTextStyleHeadline),self.applicationField,
        XFProbeLabel(@"Carpeta de destino",UIFontTextStyleHeadline),self.folderField,
        XFProbeLabel(@"Ejemplo: Documents. No crea carpetas ni usa el botón de reemplazar.",UIFontTextStyleFootnote),
        self.createButton,self.spinner,self.reportLabel,self.deleteButton,self.reportCopyButton]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    id saved=[NSUserDefaults.standardUserDefaults objectForKey:XFProbeRecordKey];
    if([saved isKindOfClass:NSDictionary.class]&&[saved[@"app"] isKindOfClass:NSString.class]&&XFProbeUUID(saved[@"path"])) {
        self.record=saved;self.applicationField.text=saved[@"app"];
        self.folderField.text=[saved[@"path"] stringByDeletingLastPathComponent];
        NSString *detail=[saved[@"report"] isKindOfClass:NSString.class]?saved[@"report"]:@"Prueba pendiente de comprobar. Su resultado no está confirmado.";
        [self showReport:detail];
    }
    [self updateControls];
}
- (void)updateControls {
    self.applicationField.enabled=!self.busy&&!self.record;
    self.folderField.enabled=!self.busy&&!self.record;
    self.createButton.enabled=!self.busy&&!self.record;
    self.deleteButton.enabled=!self.busy&&self.record!=nil;
    self.reportCopyButton.enabled=!self.busy&&self.report.length>0;
    self.navigationItem.hidesBackButton=self.busy;
    self.tabBarController.tabBar.userInteractionEnabled=!self.busy;
    self.navigationController.interactivePopGestureRecognizer.enabled=!self.busy;
    self.modalInPresentation=self.busy;
    if(self.busy)[self.spinner startAnimating];else[self.spinner stopAnimating];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if(!self.busy)self.navigationController.interactivePopGestureRecognizer.enabled=YES;
}
- (void)showReport:(NSString *)detail {
    self.report=[NSString stringWithFormat:@"PRUEBA DE CREACIÓN · AirLift\nApp: %@\nRuta: %@\n\n%@",
        self.record[@"app"]?:@"",self.record[@"path"]?:@"",detail?:@""];
    self.reportLabel.text=self.report;
    if(self.record){NSMutableDictionary *saved=[self.record mutableCopy];saved[@"report"]=detail?:@"";
        self.record=saved;[NSUserDefaults.standardUserDefaults setObject:saved forKey:XFProbeRecordKey];}
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)confirmCreate {
    if(self.busy||self.record)return;
    NSString *app=[self.applicationField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *folder=[self.folderField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    BOOL valid=app.length>0&&app.length<=255&&[app rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
    if(!folder.length||[folder hasPrefix:@"/"]||[folder containsString:@"\\"]||folder.length>3000)valid=NO;
    for(NSString *part in [folder componentsSeparatedByString:@"/"])if(!part.length||[part isEqual:@"."]||[part isEqual:@".."])valid=NO;
    if(!valid){[self alert:@"Revisa los datos" message:@"Introduce el identificador de la app y una carpeta relativa existente, por ejemplo Documents."];return;}
    NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"xitforge_prueba_%@.txt",NSUUID.UUID.UUIDString.lowercaseString]];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Crear y comprobar prueba" message:[NSString stringWithFormat:@"App: %@\nRuta: %@\n\nCierra la app de destino. Se comprobará que esta ruta esté libre antes de escribir. Después podrás eliminar la prueba.",app,path] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Crear prueba" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        typeof(self) self=weakSelf;if(!self||self.busy||self.record)return;
        self.record=@{@"app":app,@"path":path};[self.view endEditing:YES];
        [self runProbeDeleting:NO];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)confirmDelete {
    if(self.busy||!self.record)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Eliminar archivo de prueba" message:[NSString stringWithFormat:@"App: %@\nRuta: %@\n\nSe comprobará que el contenido siga siendo el texto generado por XitForge. Cierra la app de destino.",self.record[@"app"],self.record[@"path"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Comprobar y eliminar" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[weakSelf runProbeDeleting:YES];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)runProbeDeleting:(BOOL)deleting {
    if(self.busy||!self.record)return;
    self.busy=YES;[self updateControls];
    NSString *app=[self.record[@"app"] copy],*path=[self.record[@"path"] copy];
    [self showReport:deleting?@"Comprobando y eliminando la prueba…":@"Creando y comprobando la misma ruta… El resultado sigue pendiente."];
    dispatch_async(self.queue, ^{
        NSError *error=nil;
        BOOL ok=deleting?[self.backend deleteTestFileForApplication:app relativePath:path error:&error]:
            [self.backend createTestFileForApplication:app relativePath:path error:&error];
        BOOL absent=deleting&&self.backend.lastDeletionAbsenceConfirmed;
        NSString *warning=self.backend.lastDirectoryWarning;
        NSString *diagnostic=self.backend.connectionDiagnostics;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO;
            NSString *result=ok?(deleting?(absent?@"LIMPIEZA CONFIRMADA: iOS confirmó la ausencia del archivo de prueba.":@"PRUEBA RETIRADA: se conservó respaldo, pero iOS no permitió confirmar su ausencia. No se declara limpieza completa."):
                @"CREACIÓN VERIFICADA: se creó el archivo, se leyó desde esa misma ruta y el contenido coincidió. El servicio confirmó el retorno del archivo a la app."):
                [NSString stringWithFormat:@"RESULTADO INCONCLUSO\n%@",error.localizedDescription?:@"El servicio no confirmó la operación."];
            if(warning.length)result=[result stringByAppendingFormat:@"\n\nAviso: %@",warning];
            result=[result stringByAppendingFormat:@"\n\nFecha: %@\n\nDiagnóstico:\n%@",[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle],diagnostic?:@""];
            [self showReport:result];
            if(ok&&deleting&&absent){self.record=nil;[NSUserDefaults.standardUserDefaults removeObjectForKey:XFProbeRecordKey];}
            [self updateControls];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,ok?@"Prueba terminada. Consulta el resultado.":@"La prueba no se pudo confirmar. Consulta el resultado.");
        });
    });
}
- (void)copyReport {
    if(!self.report.length)return;
    [UIPasteboard.generalPasteboard setItems:@[@{@"public.utf8-plain-text":self.report}] options:@{UIPasteboardOptionLocalOnly:@YES}];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"Resultado copiado");
}
@end

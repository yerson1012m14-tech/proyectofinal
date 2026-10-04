#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "LicenseValidator.h"
#import "XITForgeFileEngine.h"

/*
 * XITFORGE - BORRAR ARCHIVOS AL DESACTIVAR
 *
 * Este archivo se agrega a MiApp/ y XcodeGen lo incluye
 * automáticamente porque project.yml usa:
 *
 *   sources:
 *     - path: MiApp
 *
 * No reemplaza HomeViewController.m.
 */


/*
 * Declaración mínima de la clase que ya existe dentro de
 * HomeViewController.m. Aquí solo declaramos los métodos y
 * propiedades que necesitamos llamar.
 */
@interface XITForgeOptionsViewController : UIViewController

@property (nonatomic, copy) NSString *game;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, strong) NSSet<NSString *> *deactivationTargetKeys;
@property (nonatomic, assign) BOOL deactivationTargetsAll;

- (NSString *)apiBaseURL;

- (NSURL *)destinationURLForOption:(id)option
                            error:(NSString **)errorOut;

- (void)deactivateAllOptions;

- (void)finishDeactivationUIWithSuccess:(BOOL)success
                            noOriginals:(BOOL)noOriginals;

@end


static const void *XITForgeDeleteManifestKey =
  &XITForgeDeleteManifestKey;

static const void *XITForgeDeletePrefetchKey =
  &XITForgeDeletePrefetchKey;


@interface XITForgeOptionsViewController (XITForgeDeleteOnDeactivate)

- (void)xf_delete_deactivateAllOptions;

- (void)xf_delete_finishDeactivationUIWithSuccess:(BOOL)success
                                      noOriginals:(BOOL)noOriginals;

- (void)xf_deleteRuleWithFallback:(NSDictionary *)rule
                       completion:(void (^)(BOOL success, NSString *message))completion;

- (void)xf_deleteProcessRules:(NSArray<NSDictionary *> *)rules
                         index:(NSUInteger)index
                    completion:(void (^)(BOOL success))completion;

@end


@implementation XITForgeOptionsViewController (XITForgeDeleteOnDeactivate)


+ (void)load {
  static dispatch_once_t onceToken;

  dispatch_once(
    &onceToken,
    ^{
      Class cls =
        NSClassFromString(
          @"XITForgeOptionsViewController"
        );

      if (!cls) {
        return;
      }


      Method originalDeactivate =
        class_getInstanceMethod(
          cls,
          @selector(
            deactivateAllOptions
          )
        );

      Method replacementDeactivate =
        class_getInstanceMethod(
          cls,
          @selector(
            xf_delete_deactivateAllOptions
          )
        );


      Method originalFinish =
        class_getInstanceMethod(
          cls,
          @selector(
            finishDeactivationUIWithSuccess:noOriginals:
          )
        );

      Method replacementFinish =
        class_getInstanceMethod(
          cls,
          @selector(
            xf_delete_finishDeactivationUIWithSuccess:noOriginals:
          )
        );


      if (
        originalDeactivate &&
        replacementDeactivate
      ) {
        method_exchangeImplementations(
          originalDeactivate,
          replacementDeactivate
        );
      }


      if (
        originalFinish &&
        replacementFinish
      ) {
        method_exchangeImplementations(
          originalFinish,
          replacementFinish
        );
      }
    }
  );
}


/*
 * =========================================================
 * DESCARGAR MANIFIESTO DE BORRADO ANTES DE DESACTIVAR
 * =========================================================
 */

- (void)xf_delete_deactivateAllOptions {

  NSNumber *inProgress =
    objc_getAssociatedObject(
      self,
      XITForgeDeletePrefetchKey
    );

  if (inProgress.boolValue) {
    return;
  }


  objc_setAssociatedObject(
    self,
    XITForgeDeletePrefetchKey,
    @YES,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC
  );


  NSString *game =
    self.game ?: @"";

  NSString *encodedGame =
    [game
      stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet
          URLQueryAllowedCharacterSet]
    ];


  NSString *base =
    [self apiBaseURL] ?: @"";

  NSString *urlString =
    [NSString
      stringWithFormat:
        @"%@/api/app/delete-files?game=%@",
        base,
        encodedGame ?: @""
    ];


  NSURL *url =
    [NSURL
      URLWithString:
        urlString
    ];


  if (!url) {

    objc_setAssociatedObject(
      self,
      XITForgeDeletePrefetchKey,
      @NO,
      OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    /*
     * Después del swizzle este selector llama al método
     * original deactivateAllOptions.
     */
    [self xf_delete_deactivateAllOptions];

    return;
  }


  NSMutableURLRequest *request =
    [NSMutableURLRequest
      requestWithURL:
        url
    ];

  request.HTTPMethod =
    @"GET";

  request.timeoutInterval =
    10.0;


  __weak typeof(self) weakSelf =
    self;


  [LicenseValidator authorizeRequest:request completion:^(BOOL authorized) {

    __strong typeof(weakSelf) authSelf = weakSelf;
    if (!authSelf) {
      return;
    }

    if (!authorized) {
      objc_setAssociatedObject(
        authSelf,
        XITForgeDeleteManifestKey,
        @[],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
      );
      objc_setAssociatedObject(
        authSelf,
        XITForgeDeletePrefetchKey,
        @NO,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
      );
      dispatch_async(dispatch_get_main_queue(), ^{
        [authSelf xf_delete_deactivateAllOptions];
      });
      return;
    }

    NSURLSessionDataTask *task =
      [[NSURLSession sharedSession]
        dataTaskWithRequest:
          request

        completionHandler:
          ^(
            NSData * _Nullable data,
            NSURLResponse * _Nullable response,
            NSError * _Nullable error
          ) {

          __strong typeof(weakSelf) strongSelf =
            weakSelf;

          if (!strongSelf) {
            return;
          }


          NSArray *deleteFiles =
            nil;


          NSHTTPURLResponse *http =
            [response
              isKindOfClass:
                [NSHTTPURLResponse class]
            ]
              ? (NSHTTPURLResponse *)response
              : nil;

          [LicenseValidator handleProtectedHTTPResponse:response];


          BOOL httpOK =
            !http ||
            (
              http.statusCode >= 200 &&
              http.statusCode <= 299
            );


          if (
            !error &&
            data.length > 0 &&
            httpOK
          ) {

            NSError *jsonError =
              nil;

            id json =
              [NSJSONSerialization
                JSONObjectWithData:
                  data
                options:
                  0
                error:
                  &jsonError
              ];


            if (
              !jsonError &&
              [json
                isKindOfClass:
                  [NSDictionary class]
              ]
            ) {

              NSDictionary *dictionary =
                (NSDictionary *)json;

              NSNumber *ok =
                [dictionary[@"ok"]
                  isKindOfClass:
                    [NSNumber class]
                ]
                  ? dictionary[@"ok"]
                  : nil;

              NSArray *items =
                [dictionary[@"deleteFiles"]
                  isKindOfClass:
                    [NSArray class]
                ]
                  ? dictionary[@"deleteFiles"]
                  : nil;


              if (
                ok.boolValue &&
                items
              ) {
                deleteFiles =
                  items;
              }
            }
          }


          objc_setAssociatedObject(
            strongSelf,
            XITForgeDeleteManifestKey,
            deleteFiles ?: @[],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
          );


          objc_setAssociatedObject(
            strongSelf,
            XITForgeDeletePrefetchKey,
            @NO,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
          );


          dispatch_async(
            dispatch_get_main_queue(),
            ^{
              /*
               * Después del swizzle llama al método ORIGINAL.
               * Si el servidor de reglas falló, DESACTIVAR
               * sigue restaurando los originales normalmente.
               */
              [strongSelf
                xf_delete_deactivateAllOptions
              ];
            }
          );
        }
      ];


    [task resume];
  }];
}


/*
 * =========================================================
 * MATCH DE REGLAS CON LA OPCIÓN QUE SE ESTÁ DESACTIVANDO
 * =========================================================
 */

- (BOOL)xf_deleteRule:
    (NSDictionary *)rule
  matchesTargets:
    (NSSet<NSString *> *)targets
  all:
    (BOOL)all {

  NSNumber *optionId =
    [rule[@"optionId"]
      isKindOfClass:
        [NSNumber class]
    ]
      ? rule[@"optionId"]
      : nil;


  if (!optionId) {
    return NO;
  }


  if (
    targets.count == 0
  ) {
    return all;
  }


  NSString *key =
    [NSString
      stringWithFormat:
        @"id:%@",
        optionId.stringValue
    ];


  return
    [targets
      containsObject:
        key
    ];
}


/*
 * =========================================================
 * RESOLVER Y BORRAR UN ARCHIVO LOCAL
 * =========================================================
 */

- (BOOL)xf_deleteLocalRule:
    (NSDictionary *)rule
  error:
    (NSString **)errorOut {

  if (errorOut) {
    *errorOut =
      nil;
  }


  NSString *route =
    [rule[@"route"]
      isKindOfClass:
        [NSString class]
    ]
      ? rule[@"route"]
      : nil;


  NSString *fileName =
    [rule[@"fileName"]
      isKindOfClass:
        [NSString class]
    ]
      ? rule[@"fileName"]
      : nil;


  NSString *bundleId =
    [rule[@"bundleId"]
      isKindOfClass:
        [NSString class]
    ]
      ? rule[@"bundleId"]
      : self.bundleId;


  if (
    route.length == 0 ||
    fileName.length == 0
  ) {

    if (errorOut) {
      *errorOut =
        @"Regla de borrado incompleta.";
    }

    return NO;
  }


  Class optionClass =
    NSClassFromString(
      @"XITForgeOption"
    );


  if (!optionClass) {

    if (errorOut) {
      *errorOut =
        @"No se encontró XITForgeOption.";
    }

    return NO;
  }


  id option =
    [[optionClass alloc]
      init
    ];


  @try {

    [option
      setValue:
        bundleId
      forKey:
        @"bundleId"
    ];

    [option
      setValue:
        route
      forKey:
        @"route"
    ];

    [option
      setValue:
        fileName
      forKey:
        @"fileName"
    ];

  } @catch (
    NSException *exception
  ) {

    if (errorOut) {
      *errorOut =
        exception.reason ?:
        @"No se pudo preparar la regla.";
    }

    return NO;
  }


  NSString *resolveError =
    nil;


  NSURL *destinationURL =
    [self
      destinationURLForOption:
        option
      error:
        &resolveError
    ];


  if (!destinationURL) {

    if (errorOut) {
      *errorOut =
        resolveError ?:
        @"No se pudo resolver la ruta del archivo.";
    }

    return NO;
  }


  NSFileManager *manager =
    [NSFileManager
      defaultManager
    ];


  /*
   * Si ya no existe, lo consideramos correctamente
   * desactivado. Así DESACTIVAR es idempotente.
   */
  if (
    ![manager
      fileExistsAtPath:
        destinationURL.path
    ]
  ) {

    NSLog(
      @"XITFORGE DEACT DELETE: ya no existe %@",
      destinationURL.path
    );

    return YES;
  }


  NSError *removeError =
    nil;


  BOOL removed =
    [manager
      removeItemAtURL:
        destinationURL
      error:
        &removeError
    ];


  if (
    !removed ||
    [manager
      fileExistsAtPath:
        destinationURL.path
    ]
  ) {

    if (errorOut) {
      *errorOut =
        removeError.localizedDescription ?:
        @"El archivo sigue existiendo después de intentar borrarlo.";
    }

    return NO;
  }


  NSLog(
    @"XITFORGE DEACT DELETE: eliminado %@",
    destinationURL.path
  );


  return YES;
}



/*
 * =========================================================
 * BORRADO LOCAL-FIRST + FALLBACK TÚNEL
 * =========================================================
 */

- (void)xf_deleteRuleWithFallback:(NSDictionary *)rule
                       completion:(void (^)(BOOL success, NSString *message))completion {

  NSString *route =
    [rule[@"route"] isKindOfClass:NSString.class] ? rule[@"route"] : nil;
  NSString *fileName =
    [rule[@"fileName"] isKindOfClass:NSString.class] ? rule[@"fileName"] : nil;
  NSString *bundleId =
    [rule[@"bundleId"] isKindOfClass:NSString.class] ? rule[@"bundleId"] : self.bundleId;

  if (route.length == 0 || fileName.length == 0 || bundleId.length == 0) {
    if (completion) completion(NO, @"Regla de borrado incompleta.");
    return;
  }

  NSString *localError = nil;
  if ([self xf_deleteLocalRule:rule error:&localError]) {
    if (completion) completion(YES, @"Eliminado mediante acceso local.");
    return;
  }

  if (![XITForgeFileEngine tunnelFallbackConfigured]) {
    if (completion) {
      completion(NO, localError.length
        ? [NSString stringWithFormat:@"%@ El Túnel no está configurado.", localError]
        : @"No se pudo borrar localmente y el Túnel no está configurado.");
    }
    return;
  }

  [XITForgeFileEngine deleteFileViaTunnelForBundleID:bundleId
                                               route:route
                                            fileName:fileName
                                          completion:^(BOOL success, NSString *message) {
    if (completion) completion(success, message);
  }];
}

- (void)xf_deleteProcessRules:(NSArray<NSDictionary *> *)rules
                         index:(NSUInteger)index
                    completion:(void (^)(BOOL success))completion {
  if (index >= rules.count) {
    if (completion) completion(YES);
    return;
  }

  NSDictionary *rule = rules[index];
  [self xf_deleteRuleWithFallback:rule completion:^(BOOL success, NSString *message) {
    if (!success) {
      NSLog(@"XITFORGE DEACT DELETE ERROR: %@", message ?: @"Sin detalle");
      if (completion) completion(NO);
      return;
    }
    [self xf_deleteProcessRules:rules index:(index + 1) completion:completion];
  }];
}

/*
 * =========================================================
 * AL TERMINAR LA RESTAURACIÓN, BORRAR LAS REGLAS ASOCIADAS
 * =========================================================
 */

- (void)xf_delete_finishDeactivationUIWithSuccess:
    (BOOL)success
  noOriginals:
    (BOOL)noOriginals {

  /*
   * Guardar los targets ANTES de llamar al finish original,
   * porque ese método los limpia.
   */
  NSSet<NSString *> *targets =
    [self.deactivationTargetKeys
      copy
    ] ?: [NSSet set];


  BOOL all =
    self.deactivationTargetsAll;


  NSArray *manifest =
    objc_getAssociatedObject(
      self,
      XITForgeDeleteManifestKey
    );


  if (
    ![manifest
      isKindOfClass:
        [NSArray class]
    ]
  ) {
    manifest =
      @[];
  }


  NSMutableArray<NSDictionary *> *matching =
    [NSMutableArray
      array
    ];


  for (id raw in manifest) {

    if (
      ![raw
        isKindOfClass:
          [NSDictionary class]
      ]
    ) {
      continue;
    }


    NSDictionary *rule =
      (NSDictionary *)raw;


    if (
      [self
        xf_deleteRule:
          rule
        matchesTargets:
          targets
        all:
          all
      ]
    ) {
      [matching
        addObject:
          rule
      ];
    }
  }


  objc_setAssociatedObject(
    self,
    XITForgeDeleteManifestKey,
    nil,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC
  );


  /*
   * Si restaurar originales falló, no seguimos borrando.
   */
  if (!success) {

    [self
      xf_delete_finishDeactivationUIWithSuccess:
        NO
      noOriginals:
        noOriginals
    ];

    return;
  }


  /*
   * Si esta opción no tiene reglas de borrado, conservar
   * exactamente el comportamiento anterior.
   */
  if (
    matching.count == 0
  ) {

    [self
      xf_delete_finishDeactivationUIWithSuccess:
        success
      noOriginals:
        noOriginals
    ];

    return;
  }


  /*
   * Procesar en serie. Cada regla intenta primero FilzaSlop/MCM y solo si
   * ese acceso falla pasa al backend compartido del Túnel.
   */
  [self xf_deleteProcessRules:matching
                         index:0
                    completion:^(BOOL allDeleted) {
    /*
     * Si no había originales pero sí había archivos configurados
     * para borrar, una eliminación correcta cuenta como una
     * desactivación real. Por eso forzamos noOriginals=NO.
     *
     * Después del swizzle este selector llama al finish ORIGINAL.
     */
    [self
      xf_delete_finishDeactivationUIWithSuccess:
        allDeleted
      noOriginals:
        NO
    ];
  }];
}

@end

- (void)activateLicense {

    [self.view endEditing:YES];

    NSString *input =
        [[self.licenseField.text
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            uppercaseString];

    if (input.length == 0) {

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:[Translations tr:@"incorrect"]
                message:nil
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [self presentViewController:alert
                           animated:YES
                         completion:nil];

        return;
    }

    /*
     * Evita pulsar varias veces mientras se valida.
     */
    self.continueButton.enabled = NO;
    self.licenseField.userInteractionEnabled = NO;

    __weak typeof(self) weakSelf = self;

    [LicenseValidator validateKey:input
                       completion:
    ^(BOOL valid,
      NSString * _Nullable reason,
      NSString * _Nullable expiresAt) {

        __strong typeof(weakSelf) strongSelf = weakSelf;

        if (!strongSelf) {
            return;
        }

        strongSelf.continueButton.enabled = YES;
        strongSelf.licenseField.userInteractionEnabled = YES;

        if (valid) {

            /*
             * Guardamos la key que el servidor aceptó.
             */
            [[NSUserDefaults standardUserDefaults]
                setObject:input
                   forKey:@"MiFilzaLicenseKey"];

            /*
             * Guardamos la fecha devuelta por el servidor.
             */
            if (expiresAt.length > 0) {

                [[NSUserDefaults standardUserDefaults]
                    setObject:expiresAt
                       forKey:@"MiFilzaLicenseExpiresAt"];

            } else {

                [[NSUserDefaults standardUserDefaults]
                    removeObjectForKey:@"MiFilzaLicenseExpiresAt"];
            }

            [[NSUserDefaults standardUserDefaults] synchronize];

            if (strongSelf.onLicenseValidated) {
                strongSelf.onLicenseValidated();
            }

            return;
        }

        NSString *message = nil;

        if ([reason isEqualToString:@"expired"]) {
            message = @"La licencia ha expirado.";
        }
        else if ([reason isEqualToString:@"revoked"]) {
            message = @"La licencia ha sido revocada.";
        }
        else if ([reason isEqualToString:@"device_limit"]) {
            message = @"Se alcanzó el límite de dispositivos.";
        }
        else if ([reason isEqualToString:@"network_error"]) {
            message = @"No se pudo conectar con el servidor.";
        }
        else if ([reason isEqualToString:@"not_found"]) {
            message = @"La licencia no existe.";
        }
        else {
            message = @"Licencia incorrecta.";
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:[Translations tr:@"incorrect"]
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [strongSelf presentViewController:alert
                                 animated:YES
                               completion:nil];
    }];
}

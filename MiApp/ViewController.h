//
//  ViewController.h
//  MiApp
//
//  Versión mejorada con Key System y UI moderna.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *fileList; // Array de diccionarios con info de archivos
@property (nonatomic, strong) NSArray *filteredFiles;   // Para búsqueda

- (void)loadFilesAtPath:(NSString *)path;
- (void)showKeyActivation;
- (BOOL)isUnlocked;

@end

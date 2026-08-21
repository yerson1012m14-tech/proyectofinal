#import "ViewController.h"
#import "KeyManager.h"
#import <objc/runtime.h>

@interface ViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *allApplications;
@property (nonatomic, strong) NSArray *filteredApplications;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FilzaSlop Premium";
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    
    [self setupNavigation];
    [self setupSearchBar];
    [self setupTableView];
    [self loadApplications];
}

- (void)setupNavigation {
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    
    UIBarButtonItem *logoutBtn = [[UIBarButtonItem alloc] initWithTitle:@"Cerrar Licencia" 
                                                                  style:UIBarButtonItemStylePlain 
                                                                 target:self 
                                                                 action:@selector(logout)];
    self.navigationItem.rightBarButtonItem = logoutBtn;
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 50)];
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.placeholder = @"Buscar App o Bundle ID...";
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];
}

- (void)setupTableView {
    CGFloat searchY = self.searchBar.frame.origin.y + self.searchBar.frame.size.height;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, searchY, self.view.bounds.size.width, self.view.bounds.size.height - searchY) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self.view addSubview:self.tableView];
}

// Carga las aplicaciones e IDs REALES instaladas en el iPhone usando LSApplicationWorkspace
- (void)loadApplications {
    NSMutableArray *appsList = [NSMutableArray array];
    
    Class LSApplicationWorkspace_class = NSClassFromString(@"LSApplicationWorkspace");
    if (LSApplicationWorkspace_class) {
        NSObject *workspace = [LSApplicationWorkspace_class performSelector:NSSelectorFromString(@"defaultWorkspace")];
        NSArray *allInstalledApps = [workspace performSelector:NSSelectorFromString(@"allInstalledApplications")];
        
        for (id app in allInstalledApps) {
            NSString *appName = [app performSelector:NSSelectorFromString(@"localizedName")];
            NSString *bundleID = [app performSelector:NSSelectorFromString(@"applicationIdentifier")];
            
            if (appName && bundleID) {
                [appsList addObject:@{
                    @"name": appName,
                    @"bundle": bundleID
                }];
            }
        }
    }
    
    // Ordenar alfabéticamente por nombre
    [appsList sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj1[@"name"] localizedCaseInsensitiveCompare:obj2[@"name"]];
    }];
    
    self.allApplications = [appsList copy];
    self.filteredApplications = [self.allApplications copy];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredApplications = [self.allApplications copy];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundle CONTAINS[cd] %@", searchText, searchText];
        self.filteredApplications = [self.allApplications filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApplications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.6];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:0.8];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    }
    
    NSDictionary *app = self.filteredApplications[indexPath.row];
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = app[@"bundle"];
    return cell;
}

- (void)logout {
    [[KeyManager sharedManager] revokeKey];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

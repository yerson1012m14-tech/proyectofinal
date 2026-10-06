#import <Foundation/Foundation.h>
#import "XITForgeFileEngine.h"

/* Server contract: originals are keyed by destination; delete rules by optionId.
   Plan the entire selection before executing any mutation. Delete rules win when
   the panel explicitly names the same destination as an original. */
static NSArray<NSDictionary *> *XFPanelDeactivationPlan(NSArray *originals, NSArray *rules,
    NSArray<NSDictionary *> *destinations, NSSet<NSNumber *> *optionIDs, NSString **error) {
    NSMutableDictionary<NSString *,NSDictionary *> *originalByPath=[NSMutableDictionary new];
    NSMutableDictionary<NSString *,NSDictionary *> *deleteByPath=[NSMutableDictionary new];
    NSMutableArray<NSString *> *deleteOrder=[NSMutableArray new];
    for(id value in originals) {
        if(![value isKindOfClass:NSDictionary.class])continue;
        NSDictionary *row=value;
        NSString *path=[XITForgeFileEngine relativePathForRoute:row[@"route"] fileName:row[@"fileName"] error:NULL];
        if(path.length&&[row[@"originalFileUrl"] isKindOfClass:NSString.class]&&[row[@"originalFileUrl"] length])originalByPath[path]=row;
    }
    for(id value in rules) {
        if(![value isKindOfClass:NSDictionary.class])continue;
        NSDictionary *row=value;
        if(![row[@"optionId"] isKindOfClass:NSNumber.class]||![optionIDs containsObject:row[@"optionId"]])continue;
        NSString *path=[XITForgeFileEngine relativePathForRoute:row[@"route"] fileName:row[@"fileName"] error:NULL];
        if(!path.length){if(error)*error=@"Una regla de borrado de la opción activa tiene una ruta inválida.";return nil;}
        if(!deleteByPath[path])[deleteOrder addObject:path];
        deleteByPath[path]=row;
    }
    NSMutableArray *actions=[NSMutableArray new];NSMutableSet *planned=[NSMutableSet new];
    for(NSDictionary *destination in destinations) {
        NSString *path=[XITForgeFileEngine relativePathForRoute:destination[@"route"] fileName:destination[@"fileName"] error:NULL];
        if(!path.length){if(error)*error=@"No se pudo identificar la ruta de la opción activa.";return nil;}
        if([planned containsObject:path])continue;
        NSDictionary *row=deleteByPath[path]?:originalByPath[path];
        if(!row){if(error)*error=[NSString stringWithFormat:@"El panel no tiene original ni regla de borrado para %@.",path];return nil;}
        NSMutableDictionary *action=[row mutableCopy];
        action[@"action"]=deleteByPath[path]?@"delete":@"replace";
        action[@"relativePath"]=path;
        if([destination[@"bundleId"] isKindOfClass:NSString.class]&&[destination[@"bundleId"] length])action[@"bundleId"]=destination[@"bundleId"];
        [actions addObject:action];[planned addObject:path];
    }
    // Additional exact files explicitly configured for a selected option are valid
    // cleanup actions too. Rules for unselected options never enter the plan.
    for(NSString *path in deleteOrder) {
        if([planned containsObject:path])continue;
        NSMutableDictionary *action=[deleteByPath[path] mutableCopy];
        action[@"action"]=@"delete";action[@"relativePath"]=path;
        [actions addObject:action];[planned addObject:path];
    }
    if(!actions.count){if(error)*error=@"El panel no tiene acciones de desactivación para esta selección.";return nil;}
    return actions;
}

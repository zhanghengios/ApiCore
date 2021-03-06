//
//  ApiCoreBase.swift
//  ApiCore
//
//  Created by Ondrej Rafaj on 09/12/2017.
//

import Foundation
import Vapor
import Fluent
import FluentPostgreSQL
import ErrorsCore
import Leaf
import FileCore


/// Default database typealias
public typealias ApiCoreDatabase = PostgreSQLDatabase

/// Default database connection type typealias
public typealias ApiCoreConnection = PostgreSQLConnection

/// Default database ID column type typealias
public typealias DbIdentifier = UUID

/// Default database port
public let DbDefaultPort: Int = 5432


/// Main ApiCore class
public class ApiCoreBase {
    
    /// Register models here
    public internal(set) static var models: [AnyModel.Type] = []
    
    /// Migration config
    public static var migrationConfig = MigrationConfig()
    
    /// Databse config
    public static var databaseConfig: DatabasesConfig?
    
    /// Blocks of code executed when new user registers
    public static var userDidRegister: [(User) -> ()] = []
    
    /// Blocks of code executed when new user tries to register
    public static var userShouldRegister: [(User) -> (Bool)] = []
        
    /// Configuration cache
    static var _configuration: Configuration?
    
    /// Enable detailed request debugging
    public static var debugRequests: Bool = false
    
    public typealias DeleteTeamWarning = (_ team: Team) -> Future<Swift.Error?>
    public typealias DeleteUserWarning = (_ user: User) -> Future<Swift.Error?>
    
    /// Fire a warning before team get's deleted (to cascade in submodules, etc ...)
    public static var deleteTeamWarning: DeleteTeamWarning?
    
    /// Fire a warning before user get's deleted (to cascade in submodules, etc ...)
    public static var deleteUserWarning: DeleteUserWarning?
    
    /// Shared middleware config
    public internal(set) static var middlewareConfig = MiddlewareConfig()
    
    /// Add futures to be executed during an installation process
    public typealias InstallFutureClosure = (_ worker: BasicWorker) throws -> Future<Void>
    public static var installFutures: [InstallFutureClosure] = []
    
    /// Registered Controllers with the API, these need to have a boot method to setup their routing
    public static var controllers: [Controller.Type] = [
        GenericController.self,
        InstallController.self,
        AuthController.self,
        UsersController.self,
        TeamsController.self,
        LogsController.self,
        ServerController.self,
        Auth.self,
        SettingsController.self
    ]
    
    /// Main configure method for ApiCore
    public static func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
        // Set max upload filesize
        if configuration.server.maxUploadFilesize ?? 0 < 50 {
            configuration.server.maxUploadFilesize = 50
        }
        let mb = Double(configuration.server.maxUploadFilesize ?? 50)
        let maxBodySize = Int(Filesize.megabyte(mb).value)
        let serverConfig = NIOServerConfig.default(maxBodySize: maxBodySize)
        services.register(serverConfig)
        
        try setupDatabase(&services)
        
        try setupEmails(&services)
        
        // Check JWT secret's security
        if env.isRelease && configuration.jwtSecret == "secret" {
            fatalError("You shouldn't be running around in a production mode with Configuration.jwt_secret set to \"secret\" as it is not very ... well, secret")
        }
        
        // CORS
        setupCORS()
        
        // Github login
        if ApiCoreBase.configuration.auth.github.enabled {
            print("Enabling Github login for \(configuration.auth.github.host)")
            let githubLogin = try GithubLoginManager(
                GithubConfig(
                    server: ApiCoreBase.configuration.auth.github.host,
                    api: ApiCoreBase.configuration.auth.github.api
                ),
                services: &services,
                jwtSecret: ApiCoreBase.configuration.jwtSecret
            )
            services.register { _ in
                githubLogin
            }
        } else {
            print("Github login disabled")
        }
        
        // Gitlab login
        if ApiCoreBase.configuration.auth.gitlab.enabled {
            print("Enabling Gitlab login for \(configuration.auth.gitlab.host)")
            let githubLogin = try GitlabLoginManager(
                GitlabConfig(
                    server: ApiCoreBase.configuration.auth.gitlab.host,
                    api: ApiCoreBase.configuration.auth.gitlab.api
                ),
                services: &services,
                jwtSecret: ApiCoreBase.configuration.jwtSecret
            )
            services.register { _ in
                githubLogin
            }
        } else {
            print("Gitlab login disabled")
        }
        
        try Auth.configure(&config, &env, &services)
        
        // Filesystem
        try setupStorage(&services)
        
        // Templates
        try services.register(LeafProvider())
        
        let templator = try Templator(packageUrl: ApiCoreBase.configuration.mail.templates)
        services.register(templator)
        
        // UUID service
        services.register(RequestIdService.self)
        
        try setupMiddlewares(&services, &env, &config)
    }
        
}

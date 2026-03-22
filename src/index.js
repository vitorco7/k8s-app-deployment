"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
require("reflect-metadata");
const typeorm_1 = require("typeorm");
const express = require("express");
const bodyParser = require("body-parser");
const routes_1 = require("./routes");
// create connection with database
// note that it's not active database connection
// TypeORM creates connection pools and uses them for your requests
typeorm_1.createConnection().then((connection) => __awaiter(void 0, void 0, void 0, function* () {
    // create express app
    const app = express();
    app.use(bodyParser.json());
    // register all application routes
    routes_1.AppRoutes.forEach(route => {
        app[route.method](route.path, (request, response, next) => {
            route.action(request, response)
                .then(() => next)
                .catch(err => next(err));
        });
    });
    // run app
    app.listen(3000);
    console.log("Express application is up and running on port 3000");
})).catch(error => console.log("TypeORM connection error: ", error));
//# sourceMappingURL=index.js.map
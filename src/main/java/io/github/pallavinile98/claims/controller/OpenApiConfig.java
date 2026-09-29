package io.github.pallavinile98.claims.controller;

import io.github.pallavinile98.claims.domain.CurrentUser;
import io.github.pallavinile98.claims.domain.Role;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.media.StringSchema;
import io.swagger.v3.oas.models.parameters.HeaderParameter;
import org.springdoc.core.customizers.OpenApiCustomizer;
import org.springdoc.core.utils.SpringDocUtils;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.Arrays;

import static io.github.pallavinile98.claims.controller.CurrentUserArgumentResolver.USER_ID_HEADER;
import static io.github.pallavinile98.claims.controller.CurrentUserArgumentResolver.USER_ROLE_HEADER;

@Configuration
public class OpenApiConfig {

    static {
        // CurrentUser is built from headers by our resolver, not from the request body or
        // query string, so hide it and document the two headers instead (below).
        SpringDocUtils.getConfig().addRequestWrapperToIgnore(CurrentUser.class);
    }

    @Bean
    OpenAPI claimsOpenApi() {
        return new OpenAPI().info(new Info()
                .title("Claims Approval API")
                .version("v1")
                .description("Submitters create and submit claims; approvers approve or reject them. "
                        + "Identity is passed in the X-User-Id and X-User-Role headers "
                        + "(demo only: there is no real authentication)."));
    }

    // Add the two identity headers to every operation so Swagger UI prompts for them.
    @Bean
    OpenApiCustomizer userHeadersCustomizer() {
        return openApi -> openApi.getPaths().values().forEach(path ->
                path.readOperations().forEach(operation -> operation
                        .addParametersItem(new HeaderParameter()
                                .name(USER_ID_HEADER)
                                .required(true)
                                .description("Caller's user id, e.g. alice")
                                .schema(new StringSchema().maxLength(100)))
                        .addParametersItem(new HeaderParameter()
                                .name(USER_ROLE_HEADER)
                                .required(true)
                                .description("Caller's role")
                                .schema(new StringSchema()._enum(
                                        Arrays.stream(Role.values()).map(Enum::name).toList())))));
    }
}

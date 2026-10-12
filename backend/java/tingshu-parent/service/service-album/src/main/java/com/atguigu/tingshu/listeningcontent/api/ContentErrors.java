package com.atguigu.tingshu.listeningcontent.api;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.ResponseEntity;
import org.springframework.core.annotation.Order;
import java.util.Map;
@Order(-2147483648) @RestControllerAdvice(assignableTypes=ContentApiController.class)
public class ContentErrors {
 @ExceptionHandler(ResponseStatusException.class) public ResponseEntity<?> handle(ResponseStatusException e){return ResponseEntity.status(e.getStatusCode()).body(Map.of("detail",e.getReason()));}
}

import 'spec.dart';

void main() {
  const path = GetDocumentPathParameters(id: 'document-1');
  const header = GetDocumentHeaderParameters(id: 'request-1');
  const cookie = GetDocumentCookieParameters(id: false);
  const query = GetDocumentQueryParameters(includeContent: false);

  const Document found = Document(id: 'document-1');
  const Problem missing = Problem(message: 'missing');
  const Upload upload = Upload(file: [1, 2]);

  assert(path.id == found.id);
  assert(header.id == 'request-1' && cookie.id == false);
  assert(query.includeContent == false);
  assert(query.copyWith(includeContent: null).includeContent == null);
  assert(upload == const Upload(file: [1, 2]) && upload.hashCode == const Upload(file: [1, 2]).hashCode);
  assert(missing.message == 'missing' && upload.file.length == 2);

  assert(Paths.documents.byId.path == '/documents/{id}');
  final docEndpoint = Paths.documents.byId('document-1');
  assert(docEndpoint.path == '/documents/{id}');

  final getOp = docEndpoint.get;
  assert(getOp.method == 'GET' && getOp.path == '/documents/{id}');
  final OperationRequest<Document, Problem> getReq = getOp
      .query(includeContent: false)
      .headers(id: 'request-1')
      .cookie(id: false)
      .request;
  assert(getReq.method == 'GET' && getReq.path == '/documents/{id}');
  assert(getReq.pathParams?['id'] == 'document-1');
  assert(getReq.query?['includeContent'] == false);
  assert(getReq.headers?['id'] == 'request-1');
  assert(getReq.cookie?['id'] == false);
  assert(getReq.decodeResponse({'id': 'document-1'}) == found);

  final directReq = getOp.withQuery(query).withHeaders(header).withCookie(cookie).request;
  assert(directReq.pathParams?['id'] == 'document-1');
  assert(directReq.query?['includeContent'] == false);

  final putOp = docEndpoint.put;
  assert(putOp.method == 'PUT' && putOp.path == '/documents/{id}');
  final OperationRequest<void, Problem> putReq = putOp.body(file: [1, 2]).request;
  assert(putReq.method == 'PUT' && putReq.contentType == 'multipart/form-data');
  assert(putReq.pathParams?['id'] == 'document-1');
  assert(putReq.errorDecoders.containsKey(404));
  final decodedErr = putReq.errorDecoders[404]!({'message': 'missing'});
  assert(decodedErr == missing);

  final directPutReq = putOp.withBody(upload).request;
  assert(directPutReq.body == upload);
}
